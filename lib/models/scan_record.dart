import 'package:json_annotation/json_annotation.dart';
import 'category.dart';

part 'scan_record.g.dart';

@JsonSerializable()
class ScanRecord {
  final int? id;
  final String resi;
  final String marketplace;
  @JsonKey(name: 'scanned_at', fromJson: _msToDateTime, toJson: _dateTimeToMs)
  final DateTime scannedAt;
  final String date; // YYYY-MM-DD
  @JsonKey(name: 'photo_path')
  final String? photoPath; // Path to captured photo
  @JsonKey(includeFromJson: false, includeToJson: false)
  final List<ScanCategory> categories;
  @JsonKey(name: 'sync_status', defaultValue: 'synced')
  final String syncStatus;

  ScanRecord({
    this.id,
    required this.resi,
    required this.marketplace,
    required this.scannedAt,
    required this.date,
    this.photoPath,
    this.categories = const [],
    this.syncStatus = 'pending',
  });

  /// For local DB (snake_case keys, excludes categories — stored in junction table)
  factory ScanRecord.fromMap(Map<String, dynamic> map) => _$ScanRecordFromJson(map);

  Map<String, dynamic> toMap() => _$ScanRecordToJson(this);

  /// Parse from Supabase response (with nested scan_categories)
  factory ScanRecord.fromSupabase(Map<String, dynamic> m) {
    List<ScanCategory> cats = [];
    final scList = m['scan_categories'] as List<dynamic>?;
    if (scList != null) {
      for (final sc in scList) {
        final catData = sc['categories'] as Map<String, dynamic>?;
        if (catData != null) {
          cats.add(ScanCategory(
            name: (catData['name'] ?? '') as String,
            color: (catData['color'] ?? '#9E9E9E') as String,
            userId: catData['user_id'] as String?,
          ));
        }
      }
    }
    return ScanRecord(
      id: m['id'] as int?,
      resi: (m['resi'] ?? '') as String,
      marketplace: (m['marketplace'] ?? '') as String,
      scannedAt: m['scanned_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['scanned_at'] as int)
          : DateTime.now(),
      date: (m['date'] ?? '') as String,
      photoPath: m['photo_url'] as String?,
      categories: cats,
      syncStatus: 'synced',
    );
  }

  ScanRecord copyWith({String? photoPath, List<ScanCategory>? categories, String? syncStatus}) {
    return ScanRecord(
      id: id,
      resi: resi,
      marketplace: marketplace,
      scannedAt: scannedAt,
      date: date,
      photoPath: photoPath ?? this.photoPath,
      categories: categories ?? this.categories,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  // Custom JSON converters for DateTime ↔ milliseconds (handles both int and String)
  static DateTime _msToDateTime(Object? v) {
    if (v == null) return DateTime.now();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.parse(v);
    return DateTime.now();
  }

  static int _dateTimeToMs(DateTime dt) => dt.millisecondsSinceEpoch;
}
