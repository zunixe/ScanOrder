# ScanOrder — Deployment & Configuration Guide

> Dokumen ini berisi semua informasi penting untuk build, konfigurasi, dan deploy aplikasi ScanOrder ke production.

---

## 1. Build Commands

### Development (Debug)
```bash
flutter pub get
flutter build apk --debug
```

### Release APK (Testing / Sideload)
```bash
flutter build apk --release --dart-define-from-file=.env
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Release AAB (Google Play Store)
```bash
flutter build appbundle --release --dart-define-from-file=.env
# Output: build/app/outputs/bundle/release/app-release.aab
```

### Build dengan Split APK (opsional, hemat size)
```bash
flutter build apk --release --split-per-abi --dart-define-from-file=.env
# Output: app-arm64-v8a-release.apk, app-armeabi-v7a-release.apk, app-x86_64-release.apk
```

> **⚠️ PENTING — WAJIB `--dart-define-from-file=.env` di semua build release!**
>
> App membaca `SUPABASE_URL` dan `SUPABASE_ANON_KEY` via `String.fromEnvironment` (build-time).
> Build **tanpa** flag ini menghasilkan APK/AAB yang **tidak bisa connect ke Supabase**:
> - Login Google gagal / error "Tidak ada koneksi ke server. Pastikan internet aktif atau server Supabase tersedia."
> - Status offline terus muncul meski internet normal.
>
> Jangan pernah build release dengan `flutter build appbundle` polos — selalu sertakan `.env`.

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
- [ ] `flutter build appbundle --release --dart-define-from-file=.env` berhasil (WAJIB sertakan `.env`, lihat Section 1)
- [ ] `key.properties` sudah dikonfigurasi (untuk release signing)
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

### 7.1. Build Release AAB

```bash
flutter clean
flutter pub get
flutter build appbundle --release --dart-define-from-file=.env
```

> Jangan lupa `--dart-define-from-file=.env` — tanpa itu Supabase tidak terhubung (lihat Section 1 & 8).

### 7.2. Upload ke Google Play Console

1. Buka [Google Play Console](https://play.google.com/console)
2. Pilih app **ScanOrder**
3. Navigasi ke **Production** (atau **Internal Testing** untuk test)
4. Klik **Create release**
5. Upload file `build/app/outputs/bundle/release/app-release.aab`
6. Isi release notes
7. Klik **Review release** → **Start rollout to Production**

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

### App tidak bisa connect ke Supabase setelah install ("Tidak ada koneksi ke server")
**Penyebab paling umum**: AAB/APK dibuild **tanpa** `--dart-define-from-file=.env`, sehingga `SUPABASE_URL`/`SUPABASE_ANON_KEY` kosong dan app masuk mode offline.

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
| `pubspec.yaml` | Root | Dependensi & metadata app |
| `android/app/build.gradle.kts` | `android/app/` | Build config, signing, splits |
| `android/build.gradle.kts` | `android/` | Project-level Gradle config |
| `android/app/proguard-rules.pro` | `android/app/` | ProGuard rules (billing keep) |
| `.env` | Root | Environment variables (jangan commit!) |
| `.env.example` | Root | Template environment variables |
| `key.properties` | `android/` | Signing config (jangan commit!) |

---

## 10. Additional Notes

- **ProGuard**: Sudah dikonfigurasi untuk keep billing classes (`-keep class com.android.vending.billing.** { *; }`).
- **Split APK**: Diaktifkan via `gradle.properties` dengan `split-apk=true`.
- **ABI Filters**: Support `armeabi-v7a`, `arm64-v8a`, `x86_64`.
- **Multi-perangkat**: Login di beberapa device akan sinkron via Supabase.
- **Guest mode**: Data guest (`user_id = NULL`) hanya lokal, tidak tersinkron ke cloud.

---

*Last updated: 2026-08-01*  
*Dokumen ini harus di-update jika ada perubahan konfigurasi build atau deploy.*
