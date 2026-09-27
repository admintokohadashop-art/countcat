class LiveSession {
  const LiveSession({this.id, required this.name, this.startedAt, required this.createdAt, required this.updatedAt});
  final int? id;
  final String name;
  final DateTime? startedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory LiveSession.fromMap(Map<String, Object?> map) => LiveSession(
        id: map['id'] as int?, name: map['name'] as String,
        startedAt: _date(map['started_at']), createdAt: DateTime.parse(map['created_at'] as String), updatedAt: DateTime.parse(map['updated_at'] as String),
      );
  Map<String, Object?> toMap() => {'id': id, 'name': name, 'started_at': startedAt?.toIso8601String(), 'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String()};
}
DateTime? _date(Object? value) => value == null ? null : DateTime.parse(value as String);
