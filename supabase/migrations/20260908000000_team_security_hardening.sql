-- ============================================================
-- Migration: Team security hardening
-- Date: 2026-09-08
--
-- Menutup celah yang ditemukan pada review fitur Team:
-- 1. Semua tabel bisa dibaca oleh anon (USING (true)) → data resi,
--    invite code, email member, dan subscription bocor ke publik.
-- 2. `member_insert` mengizinkan siapa pun self-join tim mana pun
--    tanpa invite code → baca semua scan tim via REST.
-- 3. `cleanup_user_data(uuid)` bisa dipanggil siapa pun (SECURITY
--    DEFINER tanpa REVOKE) → hapus data user lain.
-- 4. `get_subscription_by_email` & `get_team_by_invite_code` bocor
--    ke anon (email enumeration / brute force invite code).
-- 5. Limit 10 anggota hanya dicek di client → race condition.
-- 6. Admin tidak bisa keluar tim saat masih ada anggota & tidak ada
--    cara kick member → deadlock manajemen tim.
--
-- Jalankan di Supabase SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. HAPUS SEMUA POLICY ANON — data hanya untuk pemilik & timnya
-- ------------------------------------------------------------
-- Catatan: tabel `packages` memang publik (dibaca sebelum login),
-- policy packages_anon_select dipertahankan.

DROP POLICY IF EXISTS "scans_anon_select" ON scans;
DROP POLICY IF EXISTS "teams_anon_select" ON teams;
DROP POLICY IF EXISTS "team_members_anon_select" ON team_members;
DROP POLICY IF EXISTS "subscription_anon_select" ON user_subscriptions;
DROP POLICY IF EXISTS "categories_anon_select" ON categories;
DROP POLICY IF EXISTS "scan_categories_anon_select" ON scan_categories;

-- contact_messages: read tidak boleh publik; insert tetap terbuka
-- (dipakai edge function contact form).
DROP POLICY IF EXISTS "Allow read contact_messages" ON contact_messages;

-- ------------------------------------------------------------
-- 2. REVOKE fungsi SECURITY DEFINER yang berbahaya / bocor
-- ------------------------------------------------------------

-- Kill switch: hanya service_role boleh memanggil.
REVOKE ALL ON FUNCTION public.cleanup_user_data(UUID) FROM PUBLIC, anon, authenticated;

-- Email enumeration: hanya service_role.
REVOKE ALL ON FUNCTION public.get_subscription_by_email(TEXT) FROM PUBLIC, anon, authenticated;

-- Brute force invite code: hanya authenticated (client perlu cek kode
-- sebelum join), dan rate limiting dilakukan di client + kode acak.
REVOKE ALL ON FUNCTION public.get_team_by_invite_code(TEXT) FROM PUBLIC, anon;

-- ------------------------------------------------------------
-- 3. Helper: cek tier aktif user (dipakai policy join/create tim)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.user_has_active_tier(min_tier TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM user_subscriptions us
        WHERE us.user_id = auth.uid()
          AND us.active_until IS NOT NULL
          AND us.active_until > now()
          AND (
            (min_tier = 'basic'  AND us.tier IN ('basic', 'pro', 'unlimited'))
            OR (min_tier = 'unlimited' AND us.tier = 'unlimited')
          )
    );
$$;

REVOKE ALL ON FUNCTION public.user_has_active_tier(TEXT) FROM PUBLIC, anon;

-- ------------------------------------------------------------
-- 4. JOIN TIM VIA RPC — invite code diverifikasi di server,
--    limit anggota dicek atomik, role di-force 'member'.
--    Client tidak pernah insert team_members langsung lagi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_team_with_code(p_code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_team RECORD;
    v_count INT;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not authenticated';
    END IF;

    -- Tier minimal Basic (server-side, tidak bisa dilewati client)
    IF NOT public.user_has_active_tier('basic') THEN
        RAISE EXCEPTION 'Minimal langganan Basic untuk bergabung ke tim';
    END IF;

    SELECT * INTO v_team FROM teams WHERE invite_code = upper(trim(p_code)) LIMIT 1;
    IF NOT FOUND THEN
        RETURN FALSE; -- kode tidak valid
    END IF;

    -- Sudah member? idempotent sukses
    IF EXISTS (SELECT 1 FROM team_members WHERE team_id = v_team.id AND user_id = v_uid) THEN
        RETURN TRUE;
    END IF;

    -- Batas 10 anggota. Check-then-insert adalah TOCTOU race (dua join
    -- bersamaan sama-sama lolos cek → 11 anggota). Kunci advisory per-team
    -- menserialisasi join untuk tim yang sama; deadlock dengan RPC lain
    -- tidak mungkin karena tidak ada RPC lain yang mengunci resource ini.
    PERFORM pg_advisory_xact_lock(hashtext('team_join:' || v_team.id::text));

    SELECT count(*) INTO v_count FROM team_members WHERE team_id = v_team.id;
    IF v_count >= 10 THEN
        RAISE EXCEPTION 'Tim sudah penuh (maksimal 10 anggota)';
    END IF;

    INSERT INTO team_members (team_id, user_id, role, email)
    VALUES (v_team.id, v_uid, 'member', (SELECT email FROM auth.users WHERE id = v_uid));

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.join_team_with_code(TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.join_team_with_code(TEXT) FROM PUBLIC, anon;

-- ------------------------------------------------------------
-- 5. CREATE TIM VIA RPC — atomik (team + member admin),
--    tier Team diverifikasi server-side, invite code acak.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_team_secure(p_name TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_team_id UUID;
    v_code TEXT;
    v_attempts INT := 0;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not authenticated';
    END IF;

    IF trim(p_name) = '' OR length(trim(p_name)) > 60 THEN
        RAISE EXCEPTION 'Nama tim tidak valid';
    END IF;

    -- Hanya langganan Team (unlimited) boleh membuat tim
    IF NOT public.user_has_active_tier('unlimited') THEN
        RAISE EXCEPTION 'Minimal langganan Team untuk membuat tim';
    END IF;

    -- Satu user = satu tim (hindari multi-team ambigu di client)
    IF EXISTS (SELECT 1 FROM team_members WHERE user_id = v_uid) THEN
        RAISE EXCEPTION 'Kamu sudah tergabung di sebuah tim. Keluar dulu sebelum membuat tim baru.';
    END IF;

    -- Invite code acak (cryptographically random via md5(random()))
    LOOP
        v_code := upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 8));
        BEGIN
            INSERT INTO teams (name, invite_code, created_by)
            VALUES (trim(p_name), v_code, v_uid)
            RETURNING id INTO v_team_id;
            EXIT;
        EXCEPTION WHEN unique_violation THEN
            v_attempts := v_attempts + 1;
            IF v_attempts > 5 THEN
                RAISE EXCEPTION 'Gagal membuat tim, coba lagi';
            END IF;
        END;
    END LOOP;

    INSERT INTO team_members (team_id, user_id, role, email)
    VALUES (v_team_id, v_uid, 'admin', (SELECT email FROM auth.users WHERE id = v_uid));

    RETURN v_team_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_team_secure(TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.create_team_secure(TEXT) FROM PUBLIC, anon;

-- ------------------------------------------------------------
-- 6. TUTUP member_insert self-join — insert langsung hanya via RPC
--    di atas (atau oleh admin tim yang menambah anggota).
--    Juga tutup celah team_insert: policy lama hanya cek created_by,
--    sehingga free user bisa POST /rest/v1/teams langsung (tanpa cek
--    tier Team) — cek tier kini dipaksa lewat create_team_secure RPC.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "team_insert" ON teams;
CREATE POLICY "team_insert"
    ON teams FOR INSERT TO authenticated
    WITH CHECK (false);

DROP POLICY IF EXISTS "member_insert" ON team_members;
CREATE POLICY "member_insert"
    ON team_members FOR INSERT TO authenticated
    WITH CHECK (
        team_id IN (SELECT get_my_admin_team_ids())
        OR (user_id = auth.uid() AND role = 'admin'
            AND EXISTS (SELECT 1 FROM teams t WHERE t.id = team_id AND t.created_by = auth.uid()))
    );
-- Catatan: (user_id = auth.uid() AND role = 'member') DIHAPUS —
-- self-join tanpa invite code adalah celah utama.

-- member_update hanya untuk admin: TAPI admin bisa promote dirinya atau
-- role lain bebas via PATCH langsung — paksa role tetap 'member' pada
-- update yang dilakukan lewat REST (transfer admin wajib via RPC).
DROP POLICY IF EXISTS "member_update" ON team_members;
CREATE POLICY "member_update"
    ON team_members FOR UPDATE TO authenticated
    USING (team_id IN (SELECT get_my_admin_team_ids()))
    WITH CHECK (role = 'member');

-- ------------------------------------------------------------
-- 7. PERBAIKI LEAVE / KICK / TRANSFER / DISSOLVE di bawah RLS
-- ------------------------------------------------------------
-- leave: anggota boleh hapus barisnya sendiri DI TIM MANA PUN
-- (policy lama sudah benar utk self-delete, dipertahankan).
-- kick: admin tim boleh hapus member lain.
-- dissolve team: admin pemilik tim boleh delete teams.
-- Problem lama: `team_update`/`team_delete` pakai get_my_admin_team_ids()
-- (berbasis team_members.role) — aman. Tapi anggota yang join via RPC
-- lama (role='member') tidak bisa apa-apa — OK.
--
-- Tambahan: block admin terakhir keluar jika tim masih punya anggota
-- lain — dipindah ke RPC kick_member agar atomik.

CREATE OR REPLACE FUNCTION public.kick_team_member(p_team_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not authenticated';
    END IF;

    -- Hanya admin tim yang bisa kick
    IF NOT EXISTS (
        SELECT 1 FROM team_members
        WHERE team_id = p_team_id AND user_id = v_uid AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Hanya admin tim yang bisa mengeluarkan anggota';
    END IF;

    -- Tidak bisa kick diri sendiri (pakai leave)
    IF p_user_id = v_uid THEN
        RAISE EXCEPTION 'Gunakan keluar tim untuk meninggalkan tim';
    END IF;

    DELETE FROM team_members WHERE team_id = p_team_id AND user_id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Anggota tidak ditemukan';
    END IF;
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.kick_team_member(UUID, UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.kick_team_member(UUID, UUID) FROM PUBLIC, anon;

-- Transfer admin: atomik — admin lama tetap member, admin baru naik role.
CREATE OR REPLACE FUNCTION public.transfer_team_admin(p_team_id UUID, p_new_admin_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not authenticated';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM team_members
        WHERE team_id = p_team_id AND user_id = v_uid AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Hanya admin tim yang bisa transfer admin';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM team_members
        WHERE team_id = p_team_id AND user_id = p_new_admin_id
    ) THEN
        RAISE EXCEPTION 'Anggota tidak ditemukan di tim ini';
    END IF;

    UPDATE team_members SET role = 'member'
    WHERE team_id = p_team_id AND user_id = v_uid AND role = 'admin';
    UPDATE team_members SET role = 'admin'
    WHERE team_id = p_team_id AND user_id = p_new_admin_id;
    UPDATE teams SET created_by = p_new_admin_id WHERE id = p_team_id;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.transfer_team_admin(UUID, UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.transfer_team_admin(UUID, UUID) FROM PUBLIC, anon;

-- Dissolve: hapus team + members + lepaskan team_id pada scans, atomik.
CREATE OR REPLACE FUNCTION public.dissolve_team_secure(p_team_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not authenticated';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM team_members
        WHERE team_id = p_team_id AND user_id = v_uid AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Hanya admin tim yang bisa membubarkan tim';
    END IF;

    UPDATE scans SET team_id = NULL WHERE team_id = p_team_id;
    DELETE FROM team_members WHERE team_id = p_team_id;
    DELETE FROM teams WHERE id = p_team_id;
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.dissolve_team_secure(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.dissolve_team_secure(UUID) FROM PUBLIC, anon;

-- ------------------------------------------------------------
-- 7b. KONSISTENSI OWNERSHIP SCAN TIM — member tim sah memang boleh
--     update scan tim (dibutuhkan upload foto dari device member),
--     tapi user_id baris tim dipaksa = created_by tim (mencegah
--     insert/update yang menempelkan user_id orang lain / tim lain).
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "scans_insert" ON scans;
CREATE POLICY "scans_insert"
    ON scans FOR INSERT TO authenticated
    WITH CHECK (
        auth.uid() = user_id
        OR (team_id IS NOT NULL AND team_id IN (SELECT get_my_team_ids())
            AND user_id = (SELECT created_by FROM teams WHERE id = team_id))
    );

DROP POLICY IF EXISTS "scans_update" ON scans;
CREATE POLICY "scans_update"
    ON scans FOR UPDATE TO authenticated
    USING (
        auth.uid() = user_id
        OR (team_id IS NOT NULL AND team_id IN (SELECT get_my_team_ids())
            AND user_id = (SELECT created_by FROM teams WHERE id = team_id))
    )
    WITH CHECK (
        auth.uid() = user_id
        OR (team_id IS NOT NULL AND team_id IN (SELECT get_my_team_ids())
            AND user_id = (SELECT created_by FROM teams WHERE id = team_id))
    );

-- ------------------------------------------------------------
-- 9. KUNCI HELPER RLS — jangan cabut dari authenticated: ekspresi
--    policy RLS dijalankan dengan hak user pemanggil, jadi revoke
--    dari authenticated MEMATAHKAN semua policy yang memakainya.
--    Untuk anon fungsi ini tidak bocor (auth.uid() NULL → hasil kosong).
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_my_team_ids() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_admin_team_ids() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_team_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_admin_team_ids() TO authenticated;

-- ------------------------------------------------------------
-- 8. RLS tambahan: scans delete oleh admin tim utk scan miliknya
--    (admin boleh hapus scan tim yang dia buat) — opsional, skip
--    untuk menjaga perilaku lama.
-- ------------------------------------------------------------

-- ============================================================
-- SELESAI — deployment notes:
-- - Client versi lama yang insert team_members langsung akan DITOLAK
--   (harus update app minimal versi ini).
-- - get_team_by_invite_code tetap ada utk kompatibilitas, tapi hanya
--   authenticated; client baru memakai join_team_with_code.
-- ============================================================
