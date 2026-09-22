# ScanOrder — Deployment & Configuration Guide

> Dokumen ini berisi semua informasi penting untuk build, konfigurasi, dan deploy aplikasi ScanOrder ke production.
>
> **UNTUK AI AGENT**: baca Section 1 (flavor `play` vs `admin`) SEBELUM build apa pun. Salah flavor = salah app.

---

## 0. Flavors — WAJIB DIBACA

Project memakai **1 codebase, 2 Android flavors**:

| Flavor | Application ID | Nama di HP | Entry Dart | Tujuan |
|--------|---------------|------------|------------|--------|
| `play` | `com.scanorder.scanorder` | ScanOrder | `lib/main.dart` (default) | **SATU-SATUNYA yang boleh diupload ke Google Play** |
| `admin` | `com.scanorder.scanorder.admin` | ScanOrder Admin | `lib/main_admin.dart` (`-t`) | APK internal untuk pemilik. **JANGAN PERNAH diupload ke Play Store/APKPure/store mana pun** |

Aturan mutlak:
- Build untuk Play Store → **selalu** sertakan `--flavor play`.
- Build admin → selalu `-t lib/main_admin.dart` + `--flavor admin`. AppId-nya beda (suffix `.admin`) supaya bisa ter-install berdampingan dengan app user di satu HP.
- Kode admin (`lib/admin/*`) hanya pernah di-import oleh `lib/main_admin.dart`. Build user tidak menyentuhnya sama sekali (tree-shaken total). Jangan pernah meng-import `lib/admin/*` dari kode yang dijalankan build user — satu-satunya jembatan adalah `lib/core/admin_gate.dart`.
- Menu "Admin Panel" hanya muncul di halaman Settings jika: build = admin DAN login email = `zunixe@gmail.com` (lihat Section 11).

---

## 1. Build Commands

> **⚠️ SELALU gunakan script di `scripts/` untuk build rilis!**
> Build manual `flutter build ...` pernah menghasilkan artefak BASI (kode lama) karena cache inkremental korup — detail di Section 8. Script membersihkan cache dulu, jadi hasilnya selalu segar.

| Kebutuhan | Perintah | Output |
|---|---|---|
| **AAB Play Store** | `./scripts/build_play_aab.sh` | `build/app/outputs/bundle/playRelease/app-play-release.aab` |
| **APK user (sideload)** | `./scripts/build_play_apk.sh` | `build/app/outputs/flutter-apk/app-play-release.apk` |
| **APK admin** | `./scripts/build_admin_apk.sh` | `build/app/outputs/flutter-apk/app-admin-release.apk` |

Semua script otomatis: bersihkan cache → build dengan flag benar (`--flavor` + `--dart-define-from-file=.env`) → cetak path + MD5.

Referensi perintah manual (HATI-HARI, bisa basi — lihat §8):

### Development (Debug)
```bash
flutter pub get
flutter build apk --debug --flavor play
```

### Release AAB (Google Play Store) — INI YANG DIPAKAI UNTUK RILIS
```bash
./scripts/build_play_aab.sh          # REKOMENDASI
# atau manual:
flutter build appbundle --release --flavor play --dart-define-from-file=.env
# Output: build/app/outputs/bundle/playRelease/app-play-release.aab
```

### Release APK user (testing sideload)
```bash
./scripts/build_play_apk.sh          # REKOMENDASI
# atau manual:
flutter build apk --release --flavor play --dart-define-from-file=.env
# Output: build/app/outputs/flutter-apk/app-play-release.apk
```

### Release APK ADMIN (internal saja — JANGAN upload ke store)
```bash
./scripts/build_admin_apk.sh         # REKOMENDASI
# atau manual:
flutter build apk --release --flavor admin -t lib/main_admin.dart --dart-define-from-file=.env
# Output: build/app/outputs/flutter-apk/app-admin-release.apk
```

### Build dengan Split APK (opsional, hemat size)
```bash
flutter build apk --release --split-per-abi --flavor play --dart-define-from-file=.env
# Output: app-arm64-v8a-release.apk, app-armeabi-v7a-release.apk, app-x86_64-release.apk
```

> **⚠️ PENTING 1 — WAJIB `--dart-define-from-file=.env` di semua build release!**
>
> App membaca `SUPABASE_URL` dan `SUPABASE_ANON_KEY` via `String.fromEnvironment` (build-time).
> Build **tanpa** flag ini menghasilkan APK/AAB yang **tidak bisa connect ke Supabase**:
> - Login Google gagal / error "Tidak ada koneksi ke server. Pastikan internet aktif atau server Supabase tersedia."
> - Status offline terus muncul meski internet normal.
>
> Jangan pernah build release dengan `flutter build appbundle` polos — selalu sertakan `.env`.

> **⚠️ PENTING 2 — WAJIB `--flavor` di semua build Android!**
>
> Sejak penambahan flavorDimensions `store`, Gradle tidak punya varian tanpa flavor.
> - Tanpa `--flavor`, Flutter akan error atau memilih varian salah.
> - Upload ke Play Console harus dari `bundle/playRelease/app-play-release.aab` (BUKAN lagi `bundle/release/app-release.aab`).
>
> **Catatan rilis (release notes) di Play Console** wajib pakai format tag bahasa:
> `<id>Teks catatan rilis dalam Bahasa Indonesia.</id>` — tanpa tag, tombol "Berikutnya" tetap disabled.

> **Catatan**: Fitur split APK juga aktif saat build AAB jika property `split-apk` diset di `gradle.properties`.

---

## 2. Signing Configuration

File konfigurasi signing ada di `android/app/build.gradle.kts`:

```kotlin
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```

### Setup Signing Key

1. Buat file `android/key.properties` (jangan di-commit ke git!):

```properties
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=your_key_alias
storeFile=../../your_keystore.jks
```

2. Pastikan file `.jks` berada di root project (sejajar dengan `pubspec.yaml`).

3. Sudah ada di `.gitignore`:
```
android/key.properties
*.jks
```

4. Kalau `key.properties` tidak ada, build release otomatis pakai `debug` signing config.

---

## 3. Google Play Console Setup

### 3.1. App Configuration

| Setting | Value |
|---------|-------|
| **Package Name** | `com.scanorder.scanorder` |
| **Target SDK** | 35 |
| **Min SDK** | Sesuai Flutter config |
| **Compile SDK** | Sesuai Flutter config |

### 3.2. In-App Purchase Products

Buat **3 subscription products** di Google Play Console → Monetization → Products → Subscriptions:

| Product ID | Nama | Billing Period |
|------------|------|----------------|
| `scanorder_basic_monthly` | ScanOrder Basic | Monthly |
| `scanorder_pro_monthly` | ScanOrder Pro | Monthly |
| `scanorder_team_monthly` | ScanOrder Team | Monthly |

**Catatan penting**:
- Semua product harus **aktif** dan **terpublish** (minimal di internal testing track).
- Base plan harus ditambahkan ke masing-masing product.
- Harga di Play Console harus diset (meskipun nanti ditampilkan di UI aplikasi).

### 3.3. Billing Library Version

Google Play **mewajibkan** Google Play Billing Library versi **8.0.0 atau lebih baru**.

**Dependensi di `pubspec.yaml`**:
```yaml
dependencies:
  in_app_purchase: ^3.3.0
  in_app_purchase_android: ^0.5.2  # Billing Library 8.0.0+
```

**Verifikasi**: Cek `pubspec.lock` pastikan `in_app_purchase_android` versi ≥ 0.5.0.

### 3.4. Upload Keystore

Upload keystore ke Google Play (App Signing):
1. Google Play Console → Setup → App integrity → App signing
2. Pilih "Use existing app signing key" dan upload `.jks`/`.keystore`
3. Atau biarkan Google generate key baru (recommended untuk app baru)

---

## 4. Supabase Configuration

### 4.1. Environment Variables

Buat file `.env` di root project:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

File `.env.example` sudah tersedia sebagai template.

### 4.2. Flutter Configuration

Konfigurasi Supabase ada di `lib/core/supabase/supabase_service.dart`:

```dart
await Supabase.initialize(
  url: const String.fromEnvironment('SUPABASE_URL'),
  anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
);
```

> **⚠️ WAJIB**: Setiap build release harus pakai `flutter build ... --dart-define-from-file=.env`.
> Tanpa flag ini, `SUPABASE_URL`/`SUPABASE_ANON_KEY` kosong dan app berjalan offline (login gagal).

### 4.3. Database Setup

Jalankan SQL script di Supabase SQL Editor:

| File | Deskripsi |
|------|-----------|
| `supabase_team_setup.sql` | Setup tabel teams, team_members, orders, user_subscriptions |
| `supabase_user_sessions.sql` | Tabel sesi user |
| `supabase_login_history.sql` | Riwayat login |
| `team_rls_policies.sql` | Row Level Security policies |

### 4.4. RLS & Security

- Semua tabel harus enable RLS.
- Gunakan `SECURITY DEFINER` functions untuk operasi yang memerlukan elevated privileges.
- Functions penting: `get_my_team_ids()`, `get_my_admin_team_ids()`, `get_team_by_invite_code()`, `get_subscription_by_email()`

---

## 5. Key Dependencies & Versions

| Package | Versi | Purpose |
|---------|-------|---------|
| `flutter` | SDK | Framework utama |
| `sqflite_sqlcipher` | ^3.1.1+2 | Database lokal terenkripsi |
| `supabase_flutter` | ^2.8.0 | Backend-as-a-Service |
| `in_app_purchase` | ^3.3.0 | In-app purchases |
| `in_app_purchase_android` | ^0.5.2 | Android Billing Library 8.0.0+ |
| `mobile_scanner` | ^6.0.2 | Barcode scanning |
| `google_sign_in` | ^6.2.0 | Google OAuth |
| `sentry_flutter` | ^9.0.0 | Error tracking |
| `flutter_secure_storage` | ^9.2.4 | Secure storage |

---

## 6. Pre-Release Checklist

Sebelum upload ke Google Play Store:

- [ ] `flutter pub get` berhasil tanpa error
- [ ] `flutter analyze` tidak ada ERROR baru
- [ ] `flutter build appbundle --release --flavor play --dart-define-from-file=.env` berhasil (WAJIB `--flavor play` + `.env`, lihat Section 0 & 1)
- [ ] File yang diupload: `build/app/outputs/bundle/playRelease/app-play-release.aab`
- [ ] `key.properties` sudah dikonfigurasi (untuk release signing)
- [ ] **versionCode di `pubspec.yaml` lebih besar dari rilis sebelumnya** (lihat Section 7.1)
- [ ] 3 subscription products sudah dibuat & aktif di Play Console
- [ ] Play Console internal testing track sudah setup
- [ ] Supabase project sudah running & tables sudah dibuat
- [ ] Environment variables tersedia di `.env` (URL + ANON_KEY) dan build memakainya
- [ ] App signing key sudah dikonfigurasi di Play Console
- [ ] Privacy Policy URL sudah diset di Play Console
- [ ] Content rating sudah diisi di Play Console
- [ ] Screenshot & store listing sudah disiapkan

---

## 7. Deployment Steps

### 7.1. Bump Version & Build Release AAB

1. Edit `pubspec.yaml`, naikkan version:
   ```yaml
   version: 1.0.5+23   # format: namaVersi+versionCode
   ```
   - `versionCode` (angka setelah `+`) **wajib selalu NAIK** tiap upload ke Play.
   - Catatan: saat build split APK, versionCode asli dikalikan rumus `code*10+abiCode`; untuk AAB biasa dipakai apa adanya.
2. Build:
   ```bash
   flutter clean          # opsional tapi aman
   flutter pub get
   flutter build appbundle --release --flavor play --dart-define-from-file=.env
   ```
3. Hasil akhir: `build/app/outputs/bundle/playRelease/app-play-release.aab`

> Jangan lupa `--flavor play` dan `--dart-define-from-file=.env` — tanpa itu rilis gagal connect Supabase atau salah varian.

### 7.2. Upload ke Google Play Console

**Cara A — Fastlane (butuh `fastlane/play-store-key.json` valid):**
```bash
fastlane android upload           # track production
fastlane android upload_internal  # track internal testing
```
Fastfile sudah mengarah ke path `playRelease`. Status rilis `completed` = langsung tayang setelah review (tanpa staged rollout).

**Cara B — Manual via web UI:**
1. Buka https://play.google.com/console → pilih app **ScanOrder**
2. Menu **Uji dan rilis → Produksi** → tab **Rilis** → tombol **Buat rilis baru**
3. Upload AAB dari `build/app/outputs/bundle/playRelease/app-play-release.aab`
4. **Catatan rilis** — klik "Salin dari rilis sebelumnya" ATAU ketik manual dengan format tag bahasa:
   ```
   <id>Perbaikan bug dan peningkatan stabilitas.</id>
   ```
   Tanpa tag `<id>...</id>` form akan error ("teks di luar tag bahasa") dan tombol Berikutnya disabled.
5. Klik **Berikutnya** → halaman review → pastikan status **"Siap dirilis"** → **Simpan**
6. **PENTING — Publikasi terkelola AKTIF**: perubahan TIDAK otomatis terkirim.
   Buka **Ringkasan publikasi** → cek daftar perubahan → klik **"Kirim N perubahan untuk ditinjau"**
7. Tunggu pemeriksaan cepat (~2 menit) → status jadi "sedang ditinjau" → tunggu approval Google (pengalaman terakhir: ~10 menit sampai beberapa jam)
8. Setelah **Diterbitkan**, cek via link langsung:
   `https://play.google.com/store/apps/details?id=com.scanorder.scanorder`
   Muncul di hasil pencarian Play Store bisa molor beberapa jam (indeksing).

> ⚠️ Kalau ada dialog **"Ingin memulai ulang peninjauan Anda?"** berarti masih ada peninjauan lain yang sedang berjalan. Mengirim perubahan baru akan MEMBATALKAN peninjauan lama dan mulai ulang dari nol (waktu tunggu bertambah).

> 🌍 Negara distribusi produksi saat ini HANYA: **Indonesia, Malaysia, Singapura, Filipina** (tab Negara/wilayah di track Produksi). App tidak akan muncul di negara lain.

### 7.3. Testing In-App Purchase

IAP **hanya bisa di-test** dengan:
- Internal testing track (upload AAB, download via Play Store)
- Google Play testing accounts (akun dengan license testing enabled)
- **Tidak bisa** di-test dengan APK sideload biasa

Setup license testing:
1. Play Console → Setup → License testing
2. Tambahkan email tester
3. Set response to "LICENSED"

---

## 8. Troubleshooting

### Build tidak mengandung perubahan kode terbaru (APK "basi"/stale)

Gejala: sudah edit kode + build sukses, tapi APK hasilnya tetap konten lama. Cek cepat:
```bash
unzip -p <apk> lib/arm64-v8a/libapp.so | grep -ac "string unik dari kode baru"
# 0 = APK basi, padahal string ada di source
```

**Penyebab (terjadi nyata Agustus 2026):** cache inkremental Flutter (`build/` + `.dart_tool/flutter_build`) korup setelah beberapa build berjalan tumpang-tindih / sementara Android Studio dengan Dart analysis server aktif membuka project yang sama. Setelah korup, SEMUA build inkremental berikutnya memakai artefak lama — walau exit code sukses dan `flutter analyze` bersih.

**Solusi — pakai script resmi (sudah membersihkan cache otomatis):**
```bash
./scripts/build_admin_apk.sh    # atau build_play_aab.sh / build_play_apk.sh
```

Kalau terpaksa manual, bersihkan dulu:
```bash
rm -rf build .dart_tool/flutter_build
flutter build apk --release --flavor admin -t lib/main_admin.dart --dart-define-from-file=.env
```

Pencegahan: jangan jalankan dua build Flutter paralel di repo yang sama; jangan build CLI sementara IDE lagi menjalankan proses build.

### App tidak bisa connect ke Supabase setelah install ("Tidak ada koneksi ke server")**Penyebab paling umum**: AAB/APK dibuild **tanpa** `--dart-define-from-file=.env`, sehingga `SUPABASE_URL`/`SUPABASE_ANON_KEY` kosong dan app masuk mode offline.

**Cek sebelum upload** — pastikan URL Supabase benar-benar ada di dalam AAB:
```bash
# Ekstrak APK dari AAB, lalu cari URL Supabase di dalamnya
bundletool build-apks --bundle build/app/outputs/bundle/release/app-release.aab \
  --output /tmp/app.apks --overwrite
unzip -p /tmp/app.apks base-master.apk > /tmp/base.apk
strings /tmp/base.apk | grep "supabase.co"
# Output harus menampilkan URL project (mis. https://xxxx.supabase.co)
# Kalau kosong → build ulang dengan --dart-define-from-file=.env
```

**Fix**:
```bash
flutter build appbundle --release --dart-define-from-file=.env
```
Lalu upload ulang AAB ke Play Console (track yang sama, ganti bundle di draft rilis).

**Verifikasi lain**: `.env` wajib berisi kedua baris berikut (jangan hanya URL):
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

### CI/CD build (GitHub Actions)
Workflow `.github/workflows/ci_cd.yml` sudah otomatis menjalankan:
```bash
echo "SUPABASE_URL=${{ secrets.SUPABASE_URL }}" > .env
flutter build appbundle --release --dart-define-from-file=.env
```
Pastikan secrets `SUPABASE_URL` & `SUPABASE_ANON_KEY` sudah diset di GitHub repository settings. Build lokal harus meniru command ini agar hasilnya sama.

### Error: "AI provider mengembalikan error"
Biasanya terjadi saat pengaturan AI/LLM di OpenAgentic atau tool serupa. Cek:
- API key masih valid
- Quota API belum habis
- Endpoint URL benar

### Build Error: Billing Library version
Jika muncul warning/error tentang Billing Library version saat upload Play Console:
```bash
# Update dependensi
flutter pub upgrade in_app_purchase in_app_purchase_android
```

### Build Warning: Kotlin Gradle Plugin (KGP)
Saat ini ada warning tentang KGP yang akan deprecated di Flutter masa depan. Solusi:
- Tunggu update plugin yang kompatibel dengan Built-in Kotlin
- Atau downgrade Flutter (tidak direkomendasikan)
- Untuk saat ini, build masih berhasil dengan warning.

---

## 9. File Penting

| File | Lokasi | Keterangan |
|------|--------|------------|
| `pubspec.yaml` | Root | Dependensi & metadata app + version/versionCode |
| `android/app/build.gradle.kts` | `android/app/` | Build config, **flavors**, signing, splits |
| `android/build.gradle.kts` | `android/` | Project-level Gradle config |
| `android/app/proguard-rules.pro` | `android/app/` | ProGuard rules (billing keep) |
| `.env` | Root | Environment variables (jangan commit!) |
| `.env.example` | Root | Template environment variables |
| `key.properties` | `android/` | Signing config (jangan commit!) |
| `lib/main.dart` | `lib/` | Entry build USER (flavor play) + fungsi `bootstrap()` |
| `lib/main_admin.dart` | `lib/` | Entry build ADMIN (flavor admin) |
| `lib/core/admin_gate.dart` | `lib/core/` | Jembatan user↔admin (tanpa import kode admin) |
| `lib/admin/` | `lib/` | Semua modul admin panel (wiring, provider, screens) |
| `supabase_super_admin.sql` | Root | SQL setup super admin (WAJIB dijalankan utk Admin Panel) |
| `fastlane/Fastfile` | `fastlane/` | Upload otomatis ke Play (path AAB `playRelease`) |

---

## 10. Additional Notes

- **ProGuard**: Sudah dikonfigurasi untuk keep billing classes (`-keep class com.android.vending.billing.** { *; }`).
- **Split APK**: Diaktifkan via `gradle.properties` dengan `split-apk=true`.
- **ABI Filters**: Support `armeabi-v7a`, `arm64-v8a`, `x86_64`.
- **Multi-perangkat**: Login di beberapa device akan sinkron via Supabase.
- **Guest mode**: Data guest (`user_id = NULL`) hanya lokal, tidak tersinkron ke cloud.
- **Flavor `play` vs `admin`**: lihat Section 0 — jangan tertukar saat build/upload.

---

## 11. Admin Panel (build `admin` saja)

### 11.1. Cara kerja

Pola yang sama dengan project ChatYuk:

1. Build admin dibuat dengan flavor `admin` + entry `-t lib/main_admin.dart`. `main()` memanggil `wireAdmin()` (dari `lib/admin/admin_wiring.dart`) SEBELUM `bootstrap()`.
2. `wireAdmin()` mengisi field statis di `lib/core/admin_gate.dart`: `panelBuilder`, `extraProviders`, `postInit`.
3. `app.dart` menyisipkan `...AdminGate.extraProviders` ke MultiProvider; halaman Settings menampilkan tile **"Admin Panel"** hanya jika:
   - `AdminGate.enabled == true` (hanya build admin), DAN
   - email sesi login == `AdminGate.superAdminEmail` (`zunixe@gmail.com`)
4. Build user (`play`) tidak pernah meng-import `lib/admin/*` → kode admin 100% tidak ada di AAB rilis.

### 11.2. Fitur v1

- **Dashboard statistik**: scan hari ini, total scan, user terdaftar, tim aktif, langganan berbayar aktif — dari RPC `admin_stats()`.
- **Daftar user** (kartu "User Terdaftar" bisa diklik): email, tanggal daftar, jumlah scan, scan terakhir, tier — dari RPC `admin_list_users()`.
- **Browser semua scan**: daftar seluruh data tabel `scans` milik semua user, filter marketplace / tim / rentang tanggal, pagination.

### 11.3. Setup Supabase (SUDAH DITERAPKAN — 25 Agu 2026)

Sudah dieksekusi ke project Supabase ScanOrder (`rnithriviguzbfpvzrwq`) via CLI:
```
export SUPABASE_ACCESS_TOKEN=$(cat ~/.supabase_token_zunixe)
supabase db push
```
Migrasi terkait (folder `supabase/migrations/`):
- `20260825182049_super_admin_setup.sql` — fungsi + RPC + policy
- `20260825190000_fix_is_super_admin_strict.sql` — perbaikan guard NULL
- `20260825191000_admin_list_users.sql` — RPC daftar user utk Admin Panel

Isi yang terpasang di database:
1. Fungsi `public.is_super_admin()` — guard `auth.email() = 'zunixe@gmail.com'` (boolean ketat, anti-NULL)
2. RPC `public.admin_stats()` — statistik dashboard (security definer + guard)
3. RPC `public.admin_list_users()` — daftar user: id, email, created_at, total scan, scan terakhir, tier
4. Policy RLS SELECT untuk super admin di `scans`, `teams`, `team_members`

> ⚠️ Catatan CLI: migrasi dengan timestamp LEBIH KECIL dari migrasi terakhir yang sudah diterapkan akan DI-SKIP oleh `supabase db push`. Selalu pakai timestamp naik (urut waktu), atau pakai `--include-all`.

Catatan:
- File `~/.supabase_token_zunixe` berisi access token CLI (expire **24 Aug 2027**) — jangan commit.
- Verifikasi guard: jalankan `SELECT public.admin_stats();` dari sesi TANPA JWT → harus error `FORBIDDEN`.
- Kalau perlu jalankan ulang manual: copy isi `supabase_super_admin.sql` ke Supabase Dashboard → SQL Editor.

### 11.4. Build & distribusi admin

```bash
flutter build apk --release --flavor admin -t lib/main_admin.dart --dart-define-from-file=.env
```

Install APK hasilnya (`build/app/outputs/flutter-apk/app-admin-release.apk`) langsung ke HP (sideload). Bisa berdampingan dengan app user. **JANGAN upload ke Play Store/APKPure/store mana pun.**

---

## 12. Snapshot State Produksi (per Agustus 2026)

- App LIVE di produksi: rilis **220 (1.0.4)**, diterbitkan 23 Agu 2026 (~20.19 WIB) via submission #11.
- Negara produksi: Indonesia, Malaysia, Singapura, Filipina.
- Track ID Produksi: `4697960397441779547`; Alpha: `4699461360223754749`; Open testing track juga ada (rilis 220 sedang ditinjau via submission #12).
- **Publikasi terkelola AKTIF** → semua perubahan harus dikirim manual dari Ringkasan publikasi.
- GCP project tertaut: **ScanOrder (382155642792)**; Play Integrity semua respons ON.
- Link store: https://play.google.com/store/apps/details?id=com.scanorder.scanorder

---

*Last updated: 2026-08-25*  
*Dokumen ini harus di-update jika ada perubahan konfigurasi build atau deploy.*
