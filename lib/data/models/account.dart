class Account {
  const Account({this.id, required this.name, required this.description, this.photoPath, required this.createdAt, required this.updatedAt});
  final int? id; final String name; final String description; final String? photoPath; final DateTime createdAt; final DateTime updatedAt;
  factory Account.fromMap(Map<String, Object?> map) => Account(id: map['id'] as int?, name: map['name'] as String, description: map['description'] as String? ?? '', photoPath: map['photo_path'] as String?, createdAt: DateTime.parse(map['created_at'] as String), updatedAt: DateTime.parse(map['updated_at'] as String));
  Account copyWith({String? name, String? description, Object? photoPath = _unset}) => Account(id: id, name: name ?? this.name, description: description ?? this.description, photoPath: identical(photoPath, _unset) ? this.photoPath : photoPath as String?, createdAt: createdAt, updatedAt: DateTime.now().toUtc());
  static const _unset = Object();
}
