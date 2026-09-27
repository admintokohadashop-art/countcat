class HppMaster {
  const HppMaster({this.id, required this.accountId, required this.name, required this.unitAmount, this.isActive = true, required this.createdAt, required this.updatedAt});
  final int? id; final int accountId; final String name; final int unitAmount; final bool isActive; final DateTime createdAt; final DateTime updatedAt;
  factory HppMaster.fromMap(Map<String, Object?> map) => HppMaster(id: map['id'] as int?, accountId: map['account_id'] as int, name: map['name'] as String, unitAmount: map['unit_amount'] as int, isActive: (map['is_active'] as int) == 1, createdAt: DateTime.parse(map['created_at'] as String), updatedAt: DateTime.parse(map['updated_at'] as String));
}
