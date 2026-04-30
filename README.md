# ScanOrder

Aplikasi scan resi marketplace untuk mencegah double print. Mendukung tim & sinkronisasi cloud via Supabase.

## Fitur Utama

- **Scan barcode resi** — kamera rapid scan mode, auto-detect marketplace
- **Deteksi duplikat otomatis** — cek global (lokal + cloud tim)
- **Auto-detect marketplace** — Shopee, Tokopedia, TikTok, JNE, J&T, SiCepat, AnterAja, Ninja, ID Express, Lazada
- **Riwayat order** — harian + search + export CSV
- **Statistik** — breakdown per marketplace & per hari
- **Subscription & Quota** — Gratis, Basic, Pro, Team (unlimited)
- **Manajemen Tim** — buat tim, invite code, join/keluar tim
- **Sinkronisasi Cloud** — backup & restore via Supabase
- **Multi perangkat** — login di beberapa device, data tersinkron

## Paket Langganan

| Paket | Scan/bulan | Harga |
|---|---|---|
| **Gratis** | 100 | Rp 0 |
| **Basic** | 1.000 | Rp 29.000 |
| **Pro** | 5.000 | Rp 99.000 |
| **Team** | Unlimited | Rp 399.000 |

### Upgrade & Carry-over
- Upgrade (Basic→Pro, Pro→Team): sisa scan periode lama ditambahkan ke kuota baru
- Renew tier sama / downgrade: quota reset ke batas tier
- Anggota tim: scan unlimited (quota pribadi tidak berkurang)
- Keluar tim: kembali ke quota paket pribadi

## Tim

- Pemilik tim (Unlimited): buat tim, kelola anggota, lihat invite code
- Anggota tim: join via invite code, scan unlimited, history bersama
- Keluar tim: kembali ke paket pribadi, quota tetap utuh

## Arsitektur

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── db/database_helper.dart      # SQLite lokal
│   ├── supabase/
│   │   └── supabase_service.dart    # Supabase client & RPC
│   └── theme.dart
├── features/
│   ├── auth/auth_provider.dart      # Login, signup, Google auth, tim
│   ├── scan/
│   │   ├── scan_page.dart           # Kamera scanner UI
│   │   └── scan_provider.dart       # Proses scan, quota, duplikat
│   ├── history/
│   │   ├── history_page.dart        # Riwayat scan
│   │   └── history_provider.dart
│   ├── stats/
│   │   ├── stats_page.dart          # Statistik & grafik
│   │   └── stats_provider.dart
│   └── subscription/
│       ├── subscription_page.dart   # Paket, upgrade, tim UI
│       └── subscription_provider.dart
├── models/
│   ├── order.dart                   # ScannedOrder model
│   └── team.dart                    # Team & TeamMember model
└── services/
    ├── marketplace_detector.dart    # Deteksi kurir dari nomor resi
    └── quota_service.dart           # Quota, tier, cycle, cloud sync
```

## Tech Stack

- **Flutter** (Android & iOS)
- **SQLite** (sqflite) — penyimpanan lokal
- **Supabase** — auth, database, RLS, cloud sync
- **Provider** — state management
- **mobile_scanner** — barcode scanning
- **fl_chart** — grafik statistik

## Supabase Setup

Jalankan SQL di Supabase SQL Editor:

```bash
# File: supabase_team_setup.sql
```

Isi mencakup:
- Tabel: `teams`, `team_members`, `orders`, `user_subscriptions`
- Security Definer functions: `get_my_team_ids()`, `get_my_admin_team_ids()`, `get_team_by_invite_code()`
- RLS policies untuk semua tabel
- Index untuk performa

### Environment Variables

Set di Supabase dashboard atau `.env`:
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

Konfigurasi ada di `lib/core/supabase/supabase_service.dart`.

## Build & Run

```bash
# Install dependencies
flutter pub get

# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# Install ke device via ADB
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Debug Tools

Di halaman Subscription, bagian bawah ada debug toggle:
- **Debug: [Tier]** — cycle tier (Gratis → Basic → Pro → Team) tanpa carry-over
- **Reset Quota** — reset quota ke batas tier saat ini

## Kurir yang Dideteksi

| Prefix | Kurir |
|---|---|
| SPX, SPXID | Shopee |
| TTS, TKT | TikTok |
| TKP | Tokopedia |
| JN, TLJN, CGK, BDO, SUB, SRG, CM, OK, MG, MP | JNE |
| JP, JD, JA, JX, JO, JT, JNT | J&T |
| SC, SCP | SiCepat |
| AA | AnterAja |
| NV, NINJA | Ninja |
| IDE | ID Express |
| LEX, LZD | Lazada |

## Lisensi

Private — tidak untuk publikasi ke pub.dev
