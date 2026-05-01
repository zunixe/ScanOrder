-- Fix: Set pro@gmail.com subscription ke Pro
-- Jalankan di Supabase Dashboard → SQL Editor

-- 1. Cek user_id dari email
SELECT id, email FROM auth.users WHERE email = 'pro@gmail.com';

-- 2. Upsert subscription ke Pro (otomatis insert jika belum ada, update jika sudah ada)
INSERT INTO user_subscriptions (user_id, email, tier, active_from, active_until, cycle_allowance, cycle_used, storage_used, updated_at)
SELECT
  u.id,
  u.email,
  'pro',
  NOW(),
  NOW() + INTERVAL '30 days',
  5000,
  0,
  0,
  NOW()
FROM auth.users u
WHERE u.email = 'pro@gmail.com'
ON CONFLICT (user_id) DO UPDATE SET
  tier = 'pro',
  active_from = NOW(),
  active_until = NOW() + INTERVAL '30 days',
  cycle_allowance = 5000,
  cycle_used = 0,
  updated_at = NOW();

-- 3. Verifikasi
SELECT us.*, au.email FROM user_subscriptions us
JOIN auth.users au ON us.user_id = au.id
WHERE au.email = 'pro@gmail.com';
