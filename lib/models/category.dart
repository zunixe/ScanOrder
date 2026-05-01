class ScanCategory {
  final int? id;
  final String name;
  final String color; // hex color, e.g. '#FF5722'
  final String? userId;
  final DateTime createdAt;

  ScanCategory({
    this.id,
    required this.name,
    required this.color,
    this.userId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'user_id': userId,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory ScanCategory.fromMap(Map<String, dynamic> map) {
    return ScanCategory(
      id: map['id'] as int?,
      name: map['name'] as String,
      color: map['color'] as String,
      userId: map['user_id'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : DateTime.now(),
    );
  }

  ScanCategory copyWith({int? id, String? name, String? color, String? userId}) {
    return ScanCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      userId: userId ?? this.userId,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScanCategory && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
