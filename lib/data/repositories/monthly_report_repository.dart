import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../database/app_database.dart';
import '../models/monthly_report.dart';

class MonthlyReportRepository {
  MonthlyReportRepository(this._database);
  final AppDatabase _database;
  Future<List<MonthlyReport>> listReports() async { final database = await _database.database; final rows = await database.query('monthly_reports', orderBy: 'year DESC, month DESC'); return rows.map(MonthlyReport.fromMap).toList(); }
  Future<void> save(MonthlyReport report) async { final database = await _database.database; await database.insert('monthly_reports', report.toMap(), conflictAlgorithm: ConflictAlgorithm.replace); }
}
