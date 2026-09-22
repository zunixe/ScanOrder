-- ============================================================
-- Migration: Notifikasi anggota tim baru
-- Date: 2026-09-02
--
-- Saat ada user bergabung ke tim (INSERT team_members), semua
-- anggota lain (termasuk admin tim) menerima notifikasi in-app:
-- "<email> bergabung ke tim <nama tim>".
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_team_member_joined()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_team_name TEXT;
    v_new_email TEXT;
    v_member RECORD;
BEGIN
    SELECT name INTO v_team_name FROM public.teams WHERE id = NEW.team_id;
    SELECT email INTO v_new_email FROM auth.users WHERE id = NEW.user_id;
    v_new_email := COALESCE(v_new_email, '(tanpa email)');

    -- Notifikasi untuk semua anggota lain (termasuk admin tim)
    FOR v_member IN
        SELECT tm.user_id
        FROM public.team_members tm
        WHERE tm.team_id = NEW.team_id
          AND tm.user_id <> NEW.user_id
    LOOP
        INSERT INTO public.notifications (user_id, audience, title, body, type)
        VALUES (v_member.user_id, 'user',
            'Anggota Tim Baru',
            v_new_email || ' bergabung ke tim "' ||
                COALESCE(v_team_name, '(tanpa nama)') || '".',
            'team');
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_team_member_joined ON team_members;
CREATE TRIGGER on_team_member_joined
    AFTER INSERT ON team_members
    FOR EACH ROW EXECUTE FUNCTION public.handle_team_member_joined();

-- Realtime: notifikasi user dipush langsung ke device
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
    END IF;
END $$;
