-- Rename tabel di Supabase: orders → scans, order_categories → scan_categories
-- Jalankan di Supabase Dashboard → SQL Editor

-- 1. Kosongkan semua data dulu (biar bersih)
DELETE FROM order_categories;
DELETE FROM orders;

-- 2. Rename tabel orders → scans
ALTER TABLE orders RENAME TO scans;

-- 3. Rename tabel order_categories → scan_categories
ALTER TABLE order_categories RENAME TO scan_categories;

-- 4. Rename kolom order_id → scan_id di scan_categories
-- PostgreSQL: rename column
ALTER TABLE scan_categories RENAME COLUMN order_id TO scan_id;

-- 5. Verifikasi
SELECT * FROM scans LIMIT 5;
SELECT * FROM scan_categories LIMIT 5;
