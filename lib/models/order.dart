class ScannedOrder {
  final int? id;
  final String resi;
  final String marketplace;
  final DateTime scannedAt;
  final String date; // YYYY-MM-DD

  ScannedOrder({
    this.id,
    required this.resi,
    required this.marketplace,
    required this.scannedAt,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'resi': resi,
      'marketplace': marketplace,
      'scanned_at': scannedAt.millisecondsSinceEpoch,
      'date': date,
    };
  }

  factory ScannedOrder.fromMap(Map<String, dynamic> map) {
    return ScannedOrder(
      id: map['id'] as int?,
      resi: map['resi'] as String,
      marketplace: map['marketplace'] as String,
      scannedAt: DateTime.fromMillisecondsSinceEpoch(map['scanned_at'] as int),
      date: map['date'] as String,
    );
  }
}
