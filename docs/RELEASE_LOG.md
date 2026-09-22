# Release Log — ScanOrder (Google Play)

Package: `com.scanorder.scanorder` · Track produksi · Upload via `fastlane android upload`

## Aturan versionCode (BERLAKU MULAI RILIS INI)

- **Rilis sebelum 1.0.5** memakai formula lama: `buildNumber × 10`
  (…210 = 1.0.3+21, 220 = 1.0.4+22, 230 = 1.0.5+23)
- **Rilis berikutnya: versionCode = buildNumber langsung, naik +1 per rilis**
  (230 → 231 → 232 → …) — formula ×10 di `android/app/build.gradle.kts`
  sudah dihapus 1 Sep 2026

> ⚠️ **JANGAN upload build dari pubspec `1.0.5+23` saat ini** — formula baru
> menghasilkan versionCode `23` yang **DI BAWAH** 230 di store (akan ditolak).
> Rilis berikutnya WAJIB `version: 1.0.6+231` (atau lebih tinggi) di pubspec.
- Cek dulu versi tertinggi di Play sebelum upload:

```bash
# cek versionCode tertinggi di production:
curl -s -X POST \
  "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.scanorder.scanorder/edits" \
  -H "Authorization: Bearer $PLAY_TOKEN" -d '{}' # → pakai id edit untuk GET /tracks/production
```

## Riwayat rilis

| Tanggal | versionName | versionCode | Track | Catatan |
|---|---|---|---|---|
| 2025-08-xx | 1.0.3 | 210 | production | rilis reguler |
| 2025-08-25 | 1.0.4 | 220 | production | rilis reguler |
| **2026-09-01** | **1.0.5** | **230** | production | Security & stabilitas: tier subscription server-authoritative (trigger RLS), IAP receipt verification, dedupe scan antar-device, duplikat check cloud utk user personal, Free tier tanpa upload foto, IAP cancel→downgrade, fix BuildContext crash, fix notifikasi nyangkut setelah logout/register, fix sync task stale. Fitur: approval pendaftar di Admin Panel + notifikasi admin/user, notifikasi "anggota tim baru" realtime, kamera & UI fix. |

### Checklist rilis

1. Cek versionCode tertinggi di Play (lihat cara di atas)
2. Naikkan `version:` di `pubspec.yaml` — buildNumber = tertinggi + 1
   (contoh: setelah 230 → `1.0.6+231`)
3. Build: `flutter build appbundle --release --flavor play --dart-define-from-file=.env`
4. Upload: `fastlane android upload`
5. Catat di tabel atas

> ⚠️ Build `admin` (flavor admin / main_admin.dart) **TIDAK PERNAH** diupload ke Play.
