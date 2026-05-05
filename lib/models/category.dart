import 'package:json_annotation/json_annotation.dart';

part 'category.g.dart';

@JsonSerializable()
class ScanCategory {
  final int? id;
  final String name;
  final String color; // hex color, e.g. '#FF5722'
  @JsonKey(name: 'user_id')
  final String? userId;
  @JsonKey(name: 'created_at', fromJson: _msToDateTime, toJson: _dateTimeToMs)
  final DateTime createdAt;

  ScanCategory({
    this.id,
    required this.name,
    required this.color,
    this.userId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ScanCategory.fromJson(Map<String, dynamic> map) => _$ScanCategoryFromJson(map);
  Map<String, dynamic> toJson() => _$ScanCategoryToJson(this);

  factory ScanCategory.fromSupabase(Map<String, dynamic> map) => _$ScanCategoryFromJson(map);
  factory ScanCategory.fromMap(Map<String, dynamic> map) => _$ScanCategoryFromJson(map);
  Map<String, dynamic> toMap() => _$ScanCategoryToJson(this);

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

  static DateTime _msToDateTime(Object? v) {
    if (v == null) return DateTime.now();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.parse(v);
    return DateTime.now();
  }
  static int _dateTimeToMs(DateTime dt) => dt.millisecondsSinceEpoch;
}
