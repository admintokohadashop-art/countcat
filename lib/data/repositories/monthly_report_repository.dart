import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../database/app_database.dart'; import '../models/monthly_report.dart'; import 'account_repository.dart';
class MonthlyReportRepository { MonthlyReportRepository(this._database); final AppDatabase _database; Future<int?> _id() async=>(await AccountRepository(_database).activeAccount())?.id;
 Future<List<MonthlyReport>> listReports() async {final db=await _database.database;final id=await _id();final rows=await db.query('monthly_reports',where:id==null?null:'account_id=?',whereArgs:id==null?null:[id],orderBy:'year DESC, month DESC');return rows.map(MonthlyReport.fromMap).toList();}
 Future<void> save(MonthlyReport report) async {final db=await _database.database;final id=await _id(); if(id==null)return; final v=report.toMap()..['account_id']=id;await db.insert('monthly_reports',v,conflictAlgorithm:ConflictAlgorithm.replace);}}
