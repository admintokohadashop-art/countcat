import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../database/app_database.dart';
import '../models/account.dart';
class AccountRepository {
  AccountRepository(this._database); final AppDatabase _database;
  Future<List<Account>> listAccounts() async { final db = await _database.database; return (await db.query('accounts', orderBy: 'created_at ASC, id ASC')).map(Account.fromMap).toList(); }
  Future<Account?> activeAccount() async { final db = await _database.database; final rows = await db.query('settings', columns: ['value'], where: 'key = ?', whereArgs: ['active_account_id']); if (rows.isEmpty) return null; final id = int.tryParse(rows.single['value'] as String); if (id == null) return null; final accounts = await db.query('accounts', where: 'id = ?', whereArgs: [id]); return accounts.isEmpty ? null : Account.fromMap(accounts.single); }
  Future<void> setActiveAccountId(int? id) async { final db = await _database.database; if (id == null) { await db.delete('settings', where: 'key = ?', whereArgs: ['active_account_id']); return; } await db.insert('settings', {'key':'active_account_id','value':'$id','updated_at':DateTime.now().toUtc().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace); }
  Future<Account> create({required String name, String description = '', String? photoPath}) async { final db = await _database.database; final now = DateTime.now().toUtc(); final id = await db.insert('accounts', {'name':name,'description':description,'photo_path':photoPath,'created_at':now.toIso8601String(),'updated_at':now.toIso8601String()}); await setActiveAccountId(id); return Account(id:id,name:name,description:description,photoPath:photoPath,createdAt:now,updatedAt:now); }
  Future<void> update(Account account) async { final db = await _database.database; await db.update('accounts', {'name':account.name,'description':account.description,'photo_path':account.photoPath,'updated_at':DateTime.now().toUtc().toIso8601String()}, where:'id = ?', whereArgs:[account.id]); }
}
