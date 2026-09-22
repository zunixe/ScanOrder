-- Kosongkan semua data scan semua user
-- Jalankan di Supabase Dashboard → SQL Editor

-- 1. Hapus relasi scan-kategori dulu (karena ada foreign key)
DELETE FROM scan_categories;

-- 2. Hapus semua data scan
DELETE FROM scans;

-- 3. Reset jumlah scan semua user ke 0
UPDATE user_subscriptions SET cycle_used = 0, updated_at = NOW();

-- 4. Verifikasi
SELECT COUNT(*) as scan_count FROM scans;
SELECT COUNT(*) as sc_count FROM scan_categories;
