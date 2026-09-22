-- ============================================================
-- Migration: Signup approval + notifications
-- Date: 2026-09-01
--
-- Fitur:
-- 1. Tabel user_approvals — setiap user baru masuk sebagai 'pending'.
--    Admin (super admin) approve/reject dari Admin Panel.
-- 2. Tabel notifications — notifikasi in-app untuk admin & user.
-- 3. Trigger on auth.users INSERT → buat approval pending + notif admin.
-- 4. Trigger on user_approvals UPDATE → notif user saat disetujui/ditolak.
-- 5. RPC: get_my_approval_status(), admin_list_pending_approvals(),
--    admin_decide_approval() — semua guarded is_super_admin().
-- 6. Realtime publication untuk user_approvals (admin dapat push event).
-- 7. User lama (sebelum migration) di-backfill sebagai 'approved'.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Tabel user_approvals
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_approvals (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected')),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_at TIMESTAMPTZ,
    decided_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    note TEXT
);

ALTER TABLE user_approvals ENABLE ROW LEVEL SECURITY;

-- User boleh lihat status approval-nya sendiri
CREATE POLICY "approvals_select_own"
    ON user_approvals FOR SELECT TO authenticated
    USING (user_id = auth.uid());

-- Admin (super admin) boleh lihat semua
CREATE POLICY "approvals_select_admin"
    ON user_approvals FOR SELECT TO authenticated
    USING (public.is_super_admin());

-- Hanya admin boleh update (approve/reject)
CREATE POLICY "approvals_update_admin"
    ON user_approvals FOR UPDATE TO authenticated
    USING (public.is_super_admin())
    WITH CHECK (public.is_super_admin());

CREATE INDEX IF NOT EXISTS idx_approvals_status ON user_approvals(status);
CREATE INDEX IF NOT EXISTS idx_approvals_requested ON user_approvals(requested_at);

-- ------------------------------------------------------------
-- 2. Tabel notifications
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notifications (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    -- user_id NULL + audience='admin' = broadcast ke semua super admin
    audience TEXT NOT NULL DEFAULT 'user' CHECK (audience IN ('user', 'admin')),
    title TEXT NOT NULL,
    body TEXT,
    type TEXT NOT NULL DEFAULT 'info',
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications_select_own"
    ON notifications FOR SELECT TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "notifications_select_admin"
    ON notifications FOR SELECT TO authenticated
    USING (audience = 'admin' AND public.is_super_admin());

CREATE POLICY "notifications_update_own"
    ON notifications FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "notifications_update_admin"
    ON notifications FOR UPDATE TO authenticated
    USING (audience = 'admin' AND public.is_super_admin())
    WITH CHECK (audience = 'admin');

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_notifications_admin ON notifications(audience, created_at) WHERE audience = 'admin';

-- ------------------------------------------------------------
-- 3. Trigger: user baru daftar → approval pending + notif admin
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO user_approvals (user_id, email, status)
    VALUES (NEW.id, COALESCE(NEW.email, '(tanpa email)'), 'pending')
    ON CONFLICT (user_id) DO NOTHING;

    -- Notifikasi untuk semua super admin (broadcast)
    INSERT INTO notifications (user_id, audience, title, body, type)
    VALUES (NULL, 'admin',
        'Pendaftar baru',
        COALESCE(NEW.email, '(tanpa email)') || ' mendaftar dan menunggu persetujuan.',
        'signup');

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_approval ON auth.users;
CREATE TRIGGER on_auth_user_created_approval
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_approval();

-- ------------------------------------------------------------
-- 4. Trigger: status approval berubah → notif untuk user
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_approval_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NEW.status = 'approved' THEN
            INSERT INTO notifications (user_id, audience, title, body, type)
            VALUES (NEW.user_id, 'user',
                'Akun disetujui',
                'Akun Anda telah disetujui admin. Selamat menggunakan ScanOrder!',
                'approval');
        ELSIF NEW.status = 'rejected' THEN
            INSERT INTO notifications (user_id, audience, title, body, type)
            VALUES (NEW.user_id, 'user',
                'Akun ditolak',
                'Maaf, pendaftaran akun Anda tidak disetujui.' ||
                COALESCE(' Alasan: ' || NEW.note, ''),
                'approval');
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_approval_decision ON user_approvals;
CREATE TRIGGER on_approval_decision
    AFTER UPDATE OF status ON user_approvals
    FOR EACH ROW EXECUTE FUNCTION public.handle_approval_decision();

-- ------------------------------------------------------------
-- 5. RPC untuk user: cek status approval sendiri
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_approval_status()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT status FROM user_approvals
    WHERE user_id = auth.uid()
    LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_approval_status() TO authenticated;

-- ------------------------------------------------------------
-- 6. RPC untuk admin: list pending + approve/reject
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_pending_approvals()
RETURNS TABLE(
    user_id UUID,
    email TEXT,
    requested_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT ua.user_id, ua.email, ua.requested_at
    FROM user_approvals ua
    WHERE ua.status = 'pending'
      AND public.is_super_admin()
    ORDER BY ua.requested_at ASC;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_pending_approvals() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_decide_approval(
    p_user_id UUID,
    p_action TEXT,       -- 'approved' | 'rejected'
    p_note TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_updated INT;
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'unauthorized';
    END IF;
    IF p_action NOT IN ('approved', 'rejected') THEN
        RAISE EXCEPTION 'invalid action';
    END IF;

    UPDATE user_approvals
    SET status = p_action,
        decided_at = now(),
        decided_by = auth.uid(),
        note = p_note
    WHERE user_id = p_user_id
      AND status = 'pending';

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN v_updated > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_decide_approval(UUID, TEXT, TEXT) TO authenticated;

-- ------------------------------------------------------------
-- 7. Realtime: admin menerima push event signup baru
-- ------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'user_approvals'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE user_approvals;
    END IF;
END $$;

-- ------------------------------------------------------------
-- 8. Backfill: user lama dianggap sudah approved
-- ------------------------------------------------------------
INSERT INTO user_approvals (user_id, email, status, requested_at, decided_at)
SELECT u.id, COALESCE(u.email, '(tanpa email)'), 'approved',
       u.created_at, u.created_at
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM user_approvals ua WHERE ua.user_id = u.id)
ON CONFLICT (user_id) DO NOTHING;
