# ScanOrder — Design Doc Arsitektur

> Snapshot struktur & keputusan teknis project Flutter ScanOrder.
> Path: `/Users/zunixe/Documents/ScanOrder`

---

## 1. Ringkasan

**ScanOrder** adalah aplikasi mobile (Android/iOS) + web helper untuk **scan barcode resi marketplace** (Shopee, Tokopedia, TikTok, JNE, J&T, SiCepat, AnterAja, Ninja, ID Express, Lazada) dengan tujuan utama **mencegah double-print** pada alur sortir paket seller. Mendukung **multi-tier subscription** (Gratis/Basic/Pro/Team), **tim kolaboratif** dengan shared unlimited scan, **sinkronisasi cloud** via Supabase, **offline-first storage** (SQLite terenkripsi), dan **Google OAuth**. Target user: seller online / tim gudang kecil-menengah di Indonesia.

---

## 2. Tech Stack

| Lapisan | Pilihan |
|---|---|
| Framework | Flutter `^3.11.5` (Dart) |
| State Management | `provider` ^6.1.2 (ChangeNotifier) |
| Backend / Auth / DB Cloud | **Supabase** (`supabase_flutter` ^2.8.0) + Edge Function Deno (`supabase/functions/send-contact`) |
| DB Lokal | SQLite terenkripsi (`sqflite_sqlcipher` ^3.1.1+2) |
| Secure Storage | `flutter_secure_storage` ^9.2.4 |
| Scanner | `mobile_scanner` ^6.0.2 (kamera + barcode) |
| Auth | Supabase Auth + `google_sign_in` ^6.2.2 |
| IAP | `in_app_purchase` ^3.2.3 + `in_app_purchase_android` |
| Notifikasi | `flutter_local_notifications` ^18, `vibration`, `audioplayers` |
| Export | `csv` ^6, `excel` ^4.0.6, `share_plus` ^10 |
| Chart | `fl_chart` ^0.69 |
| Geo / Device | `geolocator` ^13, `device_info_plus`, `package_info_plus` |
| Image | `image_picker` ^1.1.2, `image` ^4.3, `cached_network_image` |
| Error tracking | `sentry_flutter` ^9 |
| Codegen | `freezed` ^2.5.7, `json_serializable`, `build_runner` |
| Tests | `flutter_test`, `mocktail`, `sqflite_common_ffi` |
| Build / Release | `fastlane` (Play Store), Netlify (web `account-delete.html`) |
| Localization | `flutter_localizations` + custom delegate (`app_localizations.dart`) |

---

## 3. Struktur Folder

```
lib/
├── main.dart                       # Bootstrap: monitoring, Supabase init, notif, sync queue
├── app.dart                        # MultiProvider, theme, locale, _syncUserId(auth→all providers)
├── core/
│   ├── theme.dart                  # AppTheme.light/dark
│   ├── db/database_helper.dart     # SQLite SQLCipher v3, schema orders + counters
│   ├── supabase/supabase_service.dart  # Client, RPC, RLS-aware queries, user_id filter
│   ├── security/secure_storage_service.dart  # SQLCipher key, tokens
│   ├── notifications/notification_service.dart
│   ├── monitoring/                 # monitoring_service.dart (Sentry), analytics_service.dart
│   ├── logging/logger.dart         # AppLogger wrapper
│   ├── l10n/app_localizations.dart # ID default
│   ├── backup/backup_service.dart  # JSON export/restore
│   ├── offline/                    # sync_queue_item, sync_queue_manager, exponential_backoff, conflict_resolution
│   ├── state/async_state.dart      # sealed AsyncState<T>
│   └── widgets/                    # accessibility, shimmer, pagination, async_state_builder
├── features/
│   ├── splash/                     # splash_screen, onboarding_screen
│   ├── auth/                       # auth_provider, login_dialog (signup+Google+tier select)
│   ├── scan/                       # scan_page (UI), scan_provider (logic), photo_preview_page
│   ├── history/                    # history_page, history_provider (per-user filter, export)
│   ├── stats/                      # stats_page, stats_provider (fl_chart, tier gating)
│   ├── subscription/               # subscription_page, subscription_provider (tier + IAP)
│   ├── settings/                   # settings_page, settings_provider
│   ├── team/                       # tim page + provider (invite code, members)
│   └── contact/contact_page.dart   # Form kontak → Edge Function
├── models/                         # Domain models (Order, User, Team, Quota, Subscription)
└── services/
    ├── marketplace_detector.dart   # Regex/heuristic Shopee/Tokopedia/dll
    ├── quota_service.dart          # Hitung sisa scan / bulan per user/team
    ├── sync_queue.dart             # In-memory + persisted queue
    ├── sound_service.dart          # audioplayers beep
    └── iap_service.dart            # Wrapper in_app_purchase
```

---

## 4. Arsitektur High-Level

**Pattern:** Layered + Provider (no BLoC/Riverpod), offline-first.

```
┌─────────────────────────────────────────────────────────────┐
│  UI Layer (features/*/page.dart)                            │
│      └─► ChangeNotifierProvider (per fitur)                 │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│  State / Providers (features/*/provider.dart + core/state) │
│      • ScanProvider, HistoryProvider, AuthProvider …        │
│      • Business rules: dedup, quota, tier gating            │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│  Services (services/ + core/offline/)                       │
│      • DatabaseHelper (SQLite SQLCipher) — source of truth │
│      • SyncQueue / SyncQueueManager (offline retry)         │
│      • QuotaService, IAPService, MarketplaceDetector       │
│      • NotificationService, SoundService, BackupService     │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│  Data Sources                                                │
│      • SQLite lokal (encrypted, user_id-indexed)            │
│      • Supabase (auth, Postgres tables, RPC, RLS)            │
│      • Edge Function (send-contact)                          │
└──────────────────────────────────────────────────────────────┘
```

### Alur Scan (high level)

```
[Kamera mobile_scanner] 
   └► raw barcode string
       │
       ▼
[MarketplaceDetector] ── regex heuristic ──► marketplace enum
       │
       ▼
[QuotaService.check(userId|teamId)]
   ├─ team? → unlimited (skip decrement)
   └─ free/basic/pro → check current_period_count vs limit
       │
       ▼
[Dedup check]
   ├─ local  : SELECT 1 FROM orders WHERE resi=? AND (user_id=? OR team_id=?)
   └─ cloud  : RPC orders.check_exists (best-effort, tolerate offline)
       │
       ▼
[DatabaseHelper.insert(order)]  ── INSERT INTO orders (resi, marketplace, user_id?, team_id?, scanned_by, created_at)
       │
       ▼
[SyncQueue.enqueue(order)] ── persisted (offline) ── push ke Supabase saat online
       │
       ▼
[UI feedback: sound + vibration + toast + quota badge]
```

### Boundary offline-first
- **Lokal = source of truth** untuk UX (insert langsung di SQLite, UI update instan).
- **Cloud = backup + cross-device + team-shared**, ditulis via queue dengan **exponential backoff**.
- **Conflict resolution** di `core/offline/conflict_resolution.dart` (last-write-wins by `created_at` + `scanned_by`).

---

## 5. Modul Inti

| Modul | Responsibility | Key file |
|---|---|---|
| **Auth & Identity** | Login/signup, Google OAuth, locale, tier admin flag, listener broadcast | `features/auth/auth_provider.dart`, `login_dialog.dart` |
| **Scanner & Marketplace Detection** | Render kamera, throttle detection, parse barcode → marketplace | `features/scan/scan_page.dart`, `scan_provider.dart`, `services/marketplace_detector.dart` |
| **Database Lokal** | Schema, migration, encryption, query builder, index by user_id/team_id/resi | `core/db/database_helper.dart`, `core/security/secure_storage_service.dart` |
| **Quota & Subscription** | Hitung scan/bulan, carry-over saat upgrade, gate fitur per tier | `services/quota_service.dart`, `services/iap_service.dart`, `features/subscription/*` |
| **Sync Cloud** | Enqueue, batch push, retry/backoff, conflict resolution, RLS-safe queries | `services/sync_queue.dart`, `core/offline/sync_queue_manager.dart`, `core/supabase/supabase_service.dart` |
| **Riwayat & Export** | List per-user/per-team, filter tanggal/marketplace, export CSV (berbayar) & XLSX (Team) | `features/history/history_page.dart`, `history_provider.dart` |
| **Statistik** | Chart per marketplace & harian, gating (Free: total+hari saja) | `features/stats/stats_page.dart`, `stats_provider.dart` |
| **Tim** | Buat tim, invite code, join/leave, ganti owner, history shared | `features/team/*` |
| **Backup** | Export/import JSON seluruh data user | `core/backup/backup_service.dart` |
| **Notifications & UX** | Lokal notif, sound, vibration, shimmer, async state builder | `core/notifications/notification_service.dart`, `services/sound_service.dart`, `core/widgets/*` |
| **Monitoring** | Sentry crash, analytics event, structured log | `core/monitoring/monitoring_service.dart`, `analytics_service.dart`, `core/logging/logger.dart` |

---

## 6. Data Model

### SQLite Lokal (`database_helper.dart`, schema v3)

```sql
orders(
  id INTEGER PK,
  resi TEXT NOT NULL,
  marketplace TEXT NOT NULL,        -- 'shopee' | 'tokopedia' | ...
  user_id TEXT NULLABLE,            -- NULL = guest (lokal only)
  team_id TEXT NULLABLE,
  scanned_by TEXT NULLABLE,         -- user_id yg scan (untuk team context)
  created_at INTEGER NOT NULL,
  notes TEXT NULLABLE
)
-- INDEX idx_orders_user_resi (user_id, resi)
-- INDEX idx_orders_team_resi (team_id, resi)

quota_counters(
  user_id TEXT,
  period_start INTEGER,
  count INTEGER,
  tier TEXT
)
-- Composite PK (user_id, period_start)
```

### Supabase (lihat `supabase_team_setup.sql`, `supabase_user_sessions.sql`, `supabase_login_history.sql`, `team_rls_policies.sql`)

| Tabel | Kolom kunci | Catatan |
|---|---|---|
| `orders` | id, resi, marketplace, user_id, team_id, scanned_by, created_at | Mirror lokal + RLS |
| `teams` | id, name, created_by, invite_code, created_at | Owner = admin |
| `team_members` | team_id, user_id, role, joined_at | Join via invite code |
| `user_sessions` | id, user_id, device_id, platform, last_active | `supabase_user_sessions.sql` |
| `login_history` | id, user_id, ip, ua, created_at | `supabase_login_history.sql` |
| `profiles` | id, tier, locale, created_at | Sinkron dengan Auth user |

### Multi-tenancy rules
- **Guest** (`user_id IS NULL`): data hanya di SQLite lokal, tidak pernah ke cloud.
- **User login**: `user_id = auth.uid()`, sinkron dua arah, isolated per akun.
- **Team member**: scan tak mengurangi quota pribadi; `team_id` jadi filter utama untuk history/stats.
- **RLS**: enforce `auth.uid() = user_id` di semua tabel per-user; team-scoped SELECT/UPDATE via `team_members`.

---

## 7. Alur Kunci

### A. Scan flow
1. User buka tab Scan → `ScanPage` mount kamera (`mobile_scanner` `DetectionSpeed.unrestricted`).
2. Barcode detected → `ScanProvider._onDetect(code)`.
3. `MarketplaceDetector.detect(code)` → enum.
4. `QuotaService.canScan(userId|teamId)` → jika habis, tampil upsell.
5. Dedup check (local + best-effort cloud).
6. `DatabaseHelper.insert(order)` → notifikasi UI instan.
7. `SyncQueue.enqueue(order)` → persist ke tabel queue lokal.
8. `SyncQueueManager.flush()` push ke Supabase; retry dengan exponential backoff saat offline.
9. Beep + vibration + update quota badge real-time.

### B. Login / Logout
1. `AuthProvider.signIn(email|password|google)` → Supabase Auth.
2. `MainShell._onAuthChange` → `_syncUserId()` broadcast ke semua provider.
3. `HistoryProvider.refresh()` → fetch cloud orders by `user_id` → merge ke SQLite lokal.
4. Logout: clear in-memory state, **tidak** hapus data lokal; kembali ke guest view (data guest sudah `user_id IS NULL`).

### C. Offline → Online sync
1. Setiap mutation lokal → enqueue ke `sync_queue` (persisted).
2. `SyncQueueManager` listen connectivity.
3. Backoff: 1s → 2s → 4s → … → cap 5 menit.
4. `ConflictResolution`: server row wins jika `created_at` lebih lama atau duplicate scan.
5. Mark `synced_at` di row lokal saat berhasil.

### D. Upgrade / Downgrade tier (carry-over)
1. `SubscriptionProvider.purchase(productId)` → `IAPService.verify`.
2. Jika upgrade (Basic→Pro, Pro→Team): `sisa_scan_lama + limit_baru = quota_baru`.
3. Jika renew tier sama / downgrade: reset ke `limit_tier`.
4. Team member: quota pribadi tetap, scan unlimited via team context.

### E. Team join / leave
1. Owner bikin tim → dapat `invite_code`.
2. Member input code → insert `team_members` row.
3. Saat aktif di team: `team_id` jadi context utama; scan unlimited, history tim shared.
4. Leave tim: hapus row, kembali ke paket pribadi, quota pribadi utuh.

---

## 8. Platform & Build

| Platform | Status | Build / Release |
|---|---|---|
| Android | Primary | `android/` (Kotlin DSL), `fastlane` Play Store, `build_icon.bat` / `gen_icon.bat` untuk ikon adaptive |
| iOS | Supported | `ios/`, signing via `fastlane/Appfile` + `play-store-key.json` |
| Web | Helper only | `web/account-delete.html` + `netlify.toml` (GDPR account delete flow) |
| Monitoring | All | Sentry (crash + perf), custom analytics events, structured logger |
| Background | Android | `flutter_local_notifications` untuk reminder quota |

---

## 9. Observasi & Risiko

1. **SQLCipher key management** — pastikan key di-rotate/logout aman; perlu audit `secure_storage_service.dart` untuk iOS Keychain accessibility.
2. **RLS drift** — ada 4 file SQL terpisah (`supabase_team_setup.sql`, `team_rls_policies.sql`, dll). Risiko schema drift saat deploy manual; **belum ada migration tool terpusat** (Supabase CLI migrations).
3. **IAP receipt validation** — `iap_service.dart` perlu dicek apakah validasi server-side via Supabase Edge Function (penting untuk anti-fraud Pro/Team tier).
4. **Conflict resolution tipis** — last-write-wins OK untuk event scan, tapi bisa hilang jika dua device scan barcode identik bersamaan; perlu unique constraint `(resi, team_id)` di Postgres.
5. **Test coverage gap** — 30+ file di `test/`, tapi tidak semua modul punya test (mis. `auth_provider`, `subscription_provider`, `team/*`); perlu audit `coverage/lcov_filtered.info`.
6. **Codegen debt** — pakai `freezed` + `json_serializable`; pastikan `build_runner` di-CI agar generated file konsisten.
7. **Single-process sync queue** — `sync_queue.dart` di root `services/` + `sync_queue_manager.dart` di `core/offline/`; dua abstraction layer untuk hal yang mirip — kandidat konsolidasi.
8. **Locale & first-run** — splash → onboarding gate ada, tapi belum jelas A/B eksperimen / remote config.

---

*Doc generated from snapshot repo. Update setiap perubahan besar di `lib/core/` atau schema SQL.*
