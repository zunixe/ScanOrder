import 'category.dart';

class ScannedOrder {
  final int? id;
  final String resi;
  final String marketplace;
  final DateTime scannedAt;
  final String date; // YYYY-MM-DD
  final String? photoPath; // Path to captured photo
  final List<ScanCategory> categories;

  ScannedOrder({
    this.id,
    required this.resi,
    required this.marketplace,
    required this.scannedAt,
    required this.date,
    this.photoPath,
    this.categories = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'resi': resi,
      'marketplace': marketplace,
      'scanned_at': scannedAt.millisecondsSinceEpoch,
      'date': date,
      'photo_path': photoPath,
    };
  }

  factory ScannedOrder.fromMap(Map<String, dynamic> map) {
    return ScannedOrder(
      id: map['id'] as int?,
      resi: map['resi'] as String,
      marketplace: map['marketplace'] as String,
      scannedAt: DateTime.fromMillisecondsSinceEpoch(map['scanned_at'] as int),
      date: map['date'] as String,
      photoPath: map['photo_path'] as String?,
    );
  }

  /// Parse from Supabase response (with nested scan_categories)
  factory ScannedOrder.fromSupabase(Map<String, dynamic> m) {
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
    return ScannedOrder(
      id: m['id'] as int?,
      resi: (m['resi'] ?? '') as String,
      marketplace: (m['marketplace'] ?? '') as String,
      scannedAt: m['scanned_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['scanned_at'] as int)
          : DateTime.now(),
      date: (m['date'] ?? '') as String,
      photoPath: m['photo_url'] as String?,
      categories: cats,
    );
  }

  ScannedOrder copyWith({String? photoPath, List<ScanCategory>? categories}) {
    return ScannedOrder(
      id: id,
      resi: resi,
      marketplace: marketplace,
      scannedAt: scannedAt,
      date: date,
      photoPath: photoPath ?? this.photoPath,
      categories: categories ?? this.categories,
    );
  }
}
