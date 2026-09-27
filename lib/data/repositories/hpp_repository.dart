import '../database/app_database.dart';
import '../models/hpp_master.dart';
class HppRepository { HppRepository(this._database); final AppDatabase _database;
 Future<List<HppMaster>> list(int accountId, {bool activeOnly = true}) async { final db=await _database.database; final rows=await db.query('hpp_master', where: activeOnly ? 'account_id = ? AND is_active = 1' : 'account_id = ?', whereArgs:[accountId], orderBy:'name COLLATE NOCASE'); return rows.map(HppMaster.fromMap).toList(); }
 Future<HppMaster?> find(int? id) async { if(id == null)return null; final db=await _database.database; final r=await db.query('hpp_master',where:'id = ?',whereArgs:[id]); return r.isEmpty?null:HppMaster.fromMap(r.single); }
 Future<HppMaster> create({required int accountId,required String name,required int unitAmount}) async { final now=DateTime.now().toUtc(); final db=await _database.database; final id=await db.insert('hpp_master',{'account_id':accountId,'name':name,'unit_amount':unitAmount,'is_active':1,'created_at':now.toIso8601String(),'updated_at':now.toIso8601String()}); return HppMaster(id:id,accountId:accountId,name:name,unitAmount:unitAmount,createdAt:now,updatedAt:now); }
 Future<void> update(HppMaster h) async { final db=await _database.database; await db.update('hpp_master',{'name':h.name,'unit_amount':h.unitAmount,'updated_at':DateTime.now().toUtc().toIso8601String()},where:'id=? AND account_id=?',whereArgs:[h.id,h.accountId]); }
 Future<void> deactivate(int id,int accountId) async { final db=await _database.database; await db.update('hpp_master',{'is_active':0,'updated_at':DateTime.now().toUtc().toIso8601String()},where:'id=? AND account_id=?',whereArgs:[id,accountId]); }
}
