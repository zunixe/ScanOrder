# ScanOrder

Aplikasi scan resi marketplace untuk mencegah double print. Mendukung tim & sinkronisasi cloud via Supabase.

## Fitur Utama

- **Scan barcode resi** — kamera rapid scan mode (DetectionSpeed.unrestricted), auto-detect marketplace
- **Deteksi duplikat otomatis** — cek lokal + cloud (personal & team; jika offline muncul warning)
- **Auto-detect marketplace** — Shopee, Tokopedia, TikTok, JNE, J&T, SiCepat, AnterAja, Ninja, ID Express, Lazada
- **Riwayat order per user** — data terpisah per akun, guest punya data sendiri
- **Export CSV & XLSX** — CSV untuk semua tier berbayar, XLSX khusus Team
- **Statistik** — breakdown per marketplace & per hari (Free: hanya Total & Hari ini, berbayar: grafik lengkap)
- **Sisa quota tampil di scanner** — real-time sisa scan/bulan, warning oranye saat ≤10
- **Subscription & Quota** — Gratis, Basic, Pro, Team (unlimited)
- **Login Google NATIVE (Android)** — dialog pilih akun Google bawaan Android, tanpa browser; ID token ditukar ke Supabase via `signInWithIdToken`. Fallback OAuth browser untuk iOS/Web. Sambungkan email Google dengan akun Supabase yang sudah ada
- **Tier selection saat signup** — pilih paket langsung saat daftar
- **Manajemen Tim** — buat tim, invite code, join/keluar tim
- **Sinkronisasi Cloud** — backup & restore via Supabase, data aman saat logout
- **Multi perangkat** — login di beberapa device, data tersinkron per user
- **Per-user order history** — order tersimpan dengan user_id, data terpisah antar akun
- **Halaman terkunci untuk Free** — Export & Statistik lengkap hanya untuk tier berbayar

## Paket Langganan

| Paket | Scan/bulan | Harga | Fitur |
|---|---|---|---|
| **Gratis** | 200 | Rp 0 | Scan, riwayat, statistik dasar |
| **Basic** | 3.000 | Rp 29.000 | + Export CSV, statistik lengkap |
| **Pro** | 9.000 | Rp 99.000 | + Export CSV, statistik lengkap |
| **Team** | Unlimited | Rp 399.000 | + Export XLSX, manajemen tim, sinkronisasi real-time |

### Batasan Tier Gratis
- Tidak ada fitur export (CSV/XLSX)
- Statistik hanya menampilkan Total Order & Hari ini (grafik & breakdown terkunci)
- Halaman terkunci menampilkan tombol "Lihat Paket" untuk upgrade
- Foto tidak diupload ke cloud (lokal saja)

### Upgrade & Carry-over
- Upgrade (Basic→Pro, Pro→Team): sisa scan periode lama ditambahkan ke kuota baru
- Renew tier sama / downgrade: quota reset ke batas tier
- Anggota tim: scan unlimited (quota pribadi tidak berkurang)
- Keluar tim: kembali ke quota paket pribadi

## Tim

- Pemilik tim (Unlimited): buat tim, kelola anggota, lihat invite code
- Anggota tim: join via invite code, scan unlimited, history bersama
- Keluar tim: kembali ke paket pribadi, quota tetap utuh

## Per-User Order History

- Setiap order tersimpan dengan `user_id` di database lokal (SQLite) dan Supabase
- **Guest** (belum login): data `user_id = NULL`, hanya lokal
- **User login**: data `user_id = <user_id>`, tersimpan lokal + cloud
- Saat login: data dari Supabase di-download ke lokal (by `user_id`)
- Saat logout: data user tetap aman di cloud, kembali ke data guest
- Saat login lagi: data cloud di-restore ke lokal
- Data antar akun **100% terpisah** — tidak ada pencampuran

## Arsitektur

```
lib/
├── main.dart
├── app.dart                           # MultiProvider, auth→userId sync
├── core/
│   ├── db/database_helper.dart        # SQLite lokal (v3, user_id column)
│   ├── supabase/
│   │   └── supabase_service.dart      # Supabase client, RPC, user_id filtering
│   └── theme.dart
├── features/
│   ├── auth/
│   │   ├── auth_provider.dart         # Login, signup, Google auth, admin tiers
│   │   └── login_dialog.dart          # Login/signup UI dengan tier selection
│   ├── scan/
│   │   ├── scan_page.dart             # Kamera scanner UI, quota display
│   │   └── scan_provider.dart         # Proses scan, quota, duplikat, user_id
│   ├── history/
│   │   ├── history_page.dart          # Riwayat scan, export CSV/XLSX
│   │   └── history_provider.dart      # Per-user order filtering
│   ├── stats/
│   │   ├── stats_page.dart            # Statistik (Free: partial, Paid: full)
│   │   └── stats_provider.dart
│   └── subscription/
│       ├── subscription_page.dart      # Paket, upgrade, tim UI
│       └── subscription_provider.dart  # IAP, tier management
├── models/
│   ├── order.dart                      # ScannedOrder model
│   └── team.dart                       # Team & TeamMember model
└── services/
    ├── iap_service.dart                # Google Play In-App Purchase
    ├── marketplace_detector.dart       # Deteksi kurir dari nomor resi
    └── quota_service.dart              # Quota, tier, cycle, cloud sync, user_id
```

## Tech Stack

- **Flutter** (Android & iOS)
- **SQLite** (sqflite) — penyimpanan lokal dengan user_id filtering
- **Supabase** — auth, database, RLS, cloud sync, SECURITY DEFINER functions
- **Provider** — state management
- **mobile_scanner** — barcode scanning (unrestricted speed mode)
- **fl_chart** — grafik statistik
- **excel** — export XLSX
- **csv** — export CSV
- **share_plus** — share exported files
- **in_app_purchase** — Google Play subscriptions

## Supabase Setup

Jalankan migration di `supabase/migrations/` (urut sesuai nama file) via Supabase SQL Editor atau `supabase db push`.

Isi utama (`20250101000000_team_setup.sql`):
- Tabel: `teams`, `team_members`, `orders` (dengan user_id), `user_subscriptions` (dengan email column)
- Security Definer functions: `get_my_team_ids()`, `get_my_admin_team_ids()`, `get_team_by_invite_code()`, `get_subscription_by_email()`
- RLS policies untuk semua tabel
- Index untuk performa (termasuk user_id & email)

### Environment Variables

Set di Supabase dashboard atau `.env`:
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

Konfigurasi ada di `lib/core/supabase/supabase_service.dart`.

## Google Play Console Setup

Buat 3 subscription products di Google Play Console:

| Product ID | Nama |
|---|---|
| `scanorder_basic_monthly` | Basic |
| `scanorder_pro_monthly` | Pro |
| `scanorder_team_monthly` | Team |

## Verifikasi Purchase Server-Side (Edge Function)

Tier subscription adalah **server-authoritative** — client tidak bisa menulis tier
sendiri (diblokir trigger `enforce_subscription_tier_unchanged`). Pembelian sah
diverifikasi Edge Function `verify-purchase` sebelum tier di-set di `user_subscriptions`.

### Setup sekali (Play Console)

1. [Google Cloud Console](https://console.cloud.google.com) → buat **Service Account**
   dengan role **Android Publisher** (kaitkan ke Play Console via "API access").
2. Download JSON key service account tersebut.
3. Link the project: Play Console → Setup → API access → link project Google Cloud.

### Deploy function & set secrets

```bash
supabase functions deploy verify-purchase

supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON='<tempel isi JSON key>'
supabase secrets set ANDROID_PACKAGE_NAME=com.scanorder.scanorder
```

### Flow pembelian

```
App (IAP) → insert purchase_receipts (token) → invoke verify-purchase
           → Edge Function cek token ke Google Play API (service account)
           → aktif? set tier + cycle_allowance di user_subscriptions
           → tandai purchase_receipts.verified = true
```

Client menyetel tier lokal segera setelah purchase (UX), lalu server mengoreksi
bila ada perbedaan. Device lain mendapat tier saat `syncFromCloud()`.

## Build & Run

```bash
# Install dependencies
flutter pub get

# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# Install ke device via ADB
adb install -r build/app/outputs/flutter-apk/app-release.apk
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
