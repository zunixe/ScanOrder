-- ============================================================
-- SUPER ADMIN SETUP untuk ScanOrder Admin Panel
-- Jalankan SEKALI di Supabase Dashboard → SQL Editor.
--
-- Dipakai oleh build admin (flavor `admin`, entry lib/main_admin.dart).
-- Super admin: zunixe@gmail.com (sama dengan AdminGate.superAdminEmail).
--
-- Isi:
--   1. is_super_admin()  — fungsi guard email
--   2. admin_stats()     — RPC statistik dashboard
--   3. Policy RLS read-all untuk super admin
-- ============================================================

-- ============================================================
-- 1. FUNGSI GUARD: is_super_admin()
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(auth.email()) = 'zunixe@gmail.com';
$$;

-- Hanya user login yang boleh memanggil guard/RPC ini.
REVOKE EXECUTE ON FUNCTION public.is_super_admin() FROM anon;
GRANT  EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;

-- ============================================================
-- 2. RPC STATISTIK DASHBOARD: admin_stats()
-- SECURITY DEFINER → bypass RLS, tapi dicek guard dulu.
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_stats()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN: bukan super admin';
  END IF;

  RETURN jsonb_build_object(
    'total_scans',          (SELECT count(*) FROM scans),
    'scans_today',          (SELECT count(*) FROM scans
                             WHERE date = to_char(now(), 'YYYY-MM-DD')),
    'total_users',          (SELECT count(*) FROM auth.users),
    'total_teams',          (SELECT count(*) FROM teams),
    -- Langganan berbayar aktif = tier != free DAN belum kedaluwarsa.
    'active_subscriptions', (SELECT count(*) FROM user_subscriptions
                             WHERE tier <> 'free'
                               AND (active_until IS NULL
                                    OR active_until > now()))
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_stats() FROM anon;
GRANT  EXECUTE ON FUNCTION public.admin_stats() TO authenticated;

-- ============================================================
-- 3. POLICY RLS READ-ALL untuk SUPER ADMIN
-- Browser scan membaca tabel langsung → butuh policy SELECT.
-- ============================================================

-- 3a. scans
DROP POLICY IF EXISTS "Super admin can read all scans" ON public.scans;
CREATE POLICY "Super admin can read all scans"
    ON public.scans
    FOR SELECT
    TO authenticated
    USING (public.is_super_admin());

-- 3b. teams
DROP POLICY IF EXISTS "Super admin can read all teams" ON public.teams;
CREATE POLICY "Super admin can read all teams"
    ON public.teams
    FOR SELECT
    TO authenticated
    USING (public.is_super_admin());

-- 3c. team_members
DROP POLICY IF EXISTS "Super admin can read all team_members" ON public.team_members;
CREATE POLICY "Super admin can read all team_members"
    ON public.team_members
    FOR SELECT
    TO authenticated
    USING (public.is_super_admin());

-- Selesai. Verifikasi cepat (jalankan sebagai role apa pun):
--   SELECT public.is_super_admin();      -- true hanya utk zunixe@gmail.com
--   SELECT public.admin_stats();         -- error kalau bukan super admin
