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

  ScannedOrder copyWith({List<ScanCategory>? categories}) {
    return ScannedOrder(
      id: id,
      resi: resi,
      marketplace: marketplace,
      scannedAt: scannedAt,
      date: date,
      photoPath: photoPath,
      categories: categories ?? this.categories,
    );
  }
}
