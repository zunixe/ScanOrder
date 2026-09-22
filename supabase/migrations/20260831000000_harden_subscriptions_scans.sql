-- ============================================================
-- Migration: Harden user_subscriptions + scans integrity
-- Date: 2026-08-31
--
-- Jalankan di Supabase SQL Editor.
--
-- Masalah yang diperbaiki:
-- 1. user_subscriptions bisa ditulis bebas oleh client (tier forgery).
--    → Tier/allowance/periode hanya boleh diubah oleh service_role
--      (IAP webhook / admin). Client hanya boleh update usage
--      (cycle_used naik, storage_used, email).
-- 2. Race condition insert scan antar device → duplikat row.
--    → Unique index NULL-safe.
-- 3. Purchase receipt tanpa audit trail.
--    → Tabel purchase_receipts (token dicatat, verifikasi server menyusul).
-- 4. Google-login claim subscription by email kini via RPC SECURITY DEFINER.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Lock down user_subscriptions writes
-- ------------------------------------------------------------

-- Hapus policy lama yang terlalu permisif
DROP POLICY IF EXISTS "subscription_insert_own" ON user_subscriptions;
DROP POLICY IF EXISTS "subscription_update_own" ON user_subscriptions;

-- INSERT: user boleh insert barisnya sendiri HANYA jika tier = 'free'
-- (initial sync setelah signup). Tier berbayar hanya via service_role / RPC.
CREATE POLICY "subscription_insert_own_free_only"
    ON user_subscriptions FOR INSERT TO authenticated
    WITH CHECK (
        user_id = auth.uid()
        AND (tier = 'free' OR tier IS NULL)
    );

-- SELECT & UPDATE: own-row saja
DROP POLICY IF EXISTS "subscription_select_own" ON user_subscriptions;
CREATE POLICY "subscription_select_own"
    ON user_subscriptions FOR SELECT TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "subscription_update_own" ON user_subscriptions;
CREATE POLICY "subscription_update_own"
    ON user_subscriptions FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- ------------------------------------------------------------
-- 2. Trigger guard: client tidak boleh mengubah entitlement
-- ------------------------------------------------------------
-- RLS WITH CHECK tidak bisa membandingkan OLD/NEW → pakai trigger.
-- "Privileged" = service_role (IAP webhook / admin) atau super admin.

CREATE OR REPLACE FUNCTION public.enforce_subscription_tier_unchanged()
RETURNS trigger AS $$
DECLARE
    v_is_service boolean;
    v_is_super boolean;
BEGIN
    v_is_service := coalesce(
        current_setting('request.jwt.claims', true)::json->>'role' = 'service_role',
        false
    );
    v_is_super := coalesce(public.is_super_admin(), false);
    -- Super admin juga tertangkap is_super_admin() saat memakai anon key;
    -- service_role tidak punya user email → cek keduanya.

    IF NEW.tier IS DISTINCT FROM OLD.tier AND NOT (v_is_service OR v_is_super) THEN
        RAISE EXCEPTION 'tier cannot be changed by client (use IAP verification flow)';
    END IF;

    IF NEW.cycle_allowance IS DISTINCT FROM OLD.cycle_allowance
       AND NOT (v_is_service OR v_is_super) THEN
        RAISE EXCEPTION 'cycle_allowance cannot be changed by client';
    END IF;

    -- cycle_used hanya boleh naik (counter), tidak boleh direset client
    IF NEW.cycle_used < OLD.cycle_used AND NOT (v_is_service OR v_is_super) THEN
        RAISE EXCEPTION 'cycle_used cannot be decreased by client';
    END IF;

    IF NEW.active_from IS DISTINCT FROM OLD.active_from
       AND NOT (v_is_service OR v_is_super) THEN
        RAISE EXCEPTION 'active_from cannot be changed by client';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_enforce_subscription_tier ON user_subscriptions;
CREATE TRIGGER trg_enforce_subscription_tier
    BEFORE UPDATE ON user_subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.enforce_subscription_tier_unchanged();

-- ------------------------------------------------------------
-- 3. RPC claim subscription by email (Google login link)
-- ------------------------------------------------------------
-- Menggantikan upsert client-side di QuotaService.syncFromCloud:
-- user Google-login boleh "mengklaim" subscription yang terdaftar
-- atas emailnya — email terbukti via OAuth, jadi aman via SECURITY DEFINER.

CREATE OR REPLACE FUNCTION public.claim_subscription_by_email()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_email text := auth.email();
    v_uid uuid := auth.uid();
    v_sub record;
BEGIN
    IF v_uid IS NULL OR v_email IS NULL THEN RETURN; END IF;

    -- Sudah ada subscription utk user ini → tidak perlu klaim
    IF EXISTS (SELECT 1 FROM user_subscriptions WHERE user_id = v_uid) THEN
        RETURN;
    END IF;

    SELECT * INTO v_sub
    FROM user_subscriptions
    WHERE email = v_email
      AND (user_id IS NULL OR user_id <> v_uid)
    ORDER BY updated_at DESC
    LIMIT 1;

    IF NOT FOUND THEN RETURN; END IF;

    INSERT INTO user_subscriptions
        (user_id, email, tier, active_from, active_until, cycle_allowance, cycle_used)
    VALUES
        (v_uid, v_email, v_sub.tier, v_sub.active_from, v_sub.active_until,
         v_sub.cycle_allowance, v_sub.cycle_used)
    ON CONFLICT (user_id) DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_subscription_by_email() TO authenticated;

-- ------------------------------------------------------------
-- 4. purchase_receipts: audit trail IAP
-- ------------------------------------------------------------
-- Token purchase dicatat saat client restore/beli. Verifikasi penuh
-- ke Google Play Developer API dilakukan service_role (webhook / Edge
-- Function) — tabel ini adalah sumber kebenaran token utk divalidasi.

CREATE TABLE IF NOT EXISTS purchase_receipts (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL,
    purchase_token TEXT NOT NULL,
    order_id TEXT,
    verified BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, purchase_token)
);

ALTER TABLE purchase_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "receipts_insert_own"
    ON purchase_receipts FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "receipts_select_own"
    ON purchase_receipts FOR SELECT TO authenticated
    USING (user_id = auth.uid());

-- ------------------------------------------------------------
-- 5. scans: guard duplikat antar device (NULL-safe unique)
-- ------------------------------------------------------------

-- Partial unique index lama (team_id+resi, user_id+resi) tidak mencakup NULL.
-- Buat unique index NULL-safe:
CREATE UNIQUE INDEX IF NOT EXISTS idx_scans_user_resi_nullsafe
    ON scans (COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid), resi)
    WHERE team_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_scans_team_resi_nullsafe
    ON scans (team_id, resi)
    WHERE team_id IS NOT NULL;

-- Bersihkan duplikat yang sudah ada sebelum index dibuat
-- (simpan row pertama = paling lama)
DELETE FROM scans a
USING scans b
WHERE a.id > b.id
  AND a.resi = b.resi
  AND COALESCE(a.team_id::text, '') = COALESCE(b.team_id::text, '')
  AND COALESCE(a.user_id::text, '') = COALESCE(b.user_id::text, '');

-- ------------------------------------------------------------
-- Catatan deployment
-- ------------------------------------------------------------
-- Setelah migration ini:
-- - Client TIDAK BISA lagi set tier sendiri via REST (trigger memblokir).
-- - SyncQueue.syncSubscription tetap jalan untuk usage tracking
--   (cycle_used naik, storage_used, email) — tier diabaikan client.
-- - Upgrade tier sah melalui:
--     a) IAP → app insert purchase_receipts → service_role verifikasi
--        token ke Google Play Developer API → set tier (webhook/cron), ATAU
--     b) Admin manual via dashboard (service_role).
--
-- TODO (disarankan): Edge Function `verify-purchase` dengan service_role
-- key yang memverifikasi receipt Google Play lalu menulis tier.
