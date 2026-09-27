import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class SettingsRepository {
  SettingsRepository(this._database);
  final AppDatabase _database;

  Future<int?> getGlobalHpp() async {
    final database = await _database.database;
    final rows = await database.query('settings', columns: ['value'], where: 'key = ?', whereArgs: ['global_hpp']);
    return rows.isEmpty ? null : int.tryParse(rows.single['value'] as String);
  }

  Future<void> setGlobalHpp(int amount) async {
    final database = await _database.database;
    await database.insert('settings', {'key': 'global_hpp', 'value': '$amount', 'updated_at': DateTime.now().toUtc().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
