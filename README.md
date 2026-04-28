# ScanOrder

Aplikasi scan resi marketplace (Shopee, Tokopedia, TikTok) untuk mencegah double print.

## Fitur
- Scan barcode resi dengan kamera (rapid scan mode)
- Deteksi duplikat otomatis (global)
- Auto-detect marketplace dari nomor resi
- Riwayat order harian + search
- Statistik order per hari & breakdown marketplace
- Export CSV
- Subscription (free 50 order, Pro unlimited)

## Tech Stack
- Flutter (Android & iOS)
- SQLite (sqflite)
- Provider (state management)
- mobile_scanner
- fl_chart

## Build
```bash
flutter pub get
flutter build apk --release
```
