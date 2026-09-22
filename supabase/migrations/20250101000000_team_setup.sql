-- ============================================================
-- SUPABASE FULL SETUP (v5 — updated 2025-05)
-- Jalankan semua query ini di Supabase Dashboard → SQL Editor
--
-- Changelog dari v4 ke v5:
-- - Tambah policy "Team members can read admin categories" di categories
-- - Tambah policy "Team members can read team scan_categories" di scan_categories
-- - Update seed data packages (hapus info storage, tambah Dukungan prioritas untuk Team)
-- - Tambah tabel contact_messages
-- - Tambah SQL migrasi: backfill team_id pada scans lama milik anggota tim
-- ============================================================

-- ============================================================
-- 1. TABLE: scans (dulunya orders)
-- ============================================================

CREATE TABLE IF NOT EXISTS scans (
    id BIGINT PRIMARY KEY DEFAULT nextval('scans_id_seq'),
    device_id TEXT NOT NULL DEFAULT 'unknown',
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    resi TEXT NOT NULL,
    marketplace TEXT NOT NULL,
    scanned_at BIGINT NOT NULL,
    date TEXT NOT NULL,
    photo_url TEXT,
    team_id UUID REFERENCES teams(id) ON DELETE SET NULL,
    scanned_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Sequence untuk auto-increment id
CREATE SEQUENCE IF NOT EXISTS scans_id_seq;
ALTER SEQUENCE scans_id_seq OWNED BY scans.id;
ALTER TABLE scans ALTER COLUMN id SET DEFAULT nextval('scans_id_seq');

-- Jika tabel orders sudah ada, rename ke scans
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'orders') AND NOT EXISTS (SELECT FROM pg_tables WHERE tablename = 'scans') THEN
        ALTER TABLE orders RENAME TO scans;
    END IF;
END $$;

-- Kolom tambahan jika belum ada
ALTER TABLE scans ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE scans ADD COLUMN IF NOT EXISTS team_id UUID;
ALTER TABLE scans ADD COLUMN IF NOT EXISTS scanned_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- ============================================================
-- 2. TABLE: teams
-- ============================================================

CREATE TABLE IF NOT EXISTS teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    invite_code TEXT NOT NULL UNIQUE,
    created_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 3. TABLE: team_members
-- ============================================================

CREATE TABLE IF NOT EXISTS team_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member',
    email TEXT,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(team_id, user_id)
);

-- ============================================================
-- 4. TABLE: user_subscriptions
-- ============================================================

CREATE TABLE IF NOT EXISTS user_subscriptions (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    tier TEXT NOT NULL DEFAULT 'free',
    active_from TIMESTAMPTZ,
    active_until TIMESTAMPTZ,
    cycle_allowance INTEGER NOT NULL DEFAULT 10,
    cycle_used INTEGER NOT NULL DEFAULT 0,
    storage_used BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 5. TABLE: categories
-- ============================================================

CREATE TABLE IF NOT EXISTS categories (
    id BIGINT PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 6. TABLE: scan_categories (dulunya order_categories)
-- ============================================================

CREATE TABLE IF NOT EXISTS scan_categories (
    id BIGINT PRIMARY KEY,
    scan_id BIGINT REFERENCES scans(id) ON DELETE CASCADE,
    category_id BIGINT REFERENCES categories(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(scan_id, category_id)
);

-- Jika tabel order_categories sudah ada, rename + migrate
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'order_categories') AND NOT EXISTS (SELECT FROM pg_tables WHERE tablename = 'scan_categories') THEN
        ALTER TABLE order_categories RENAME TO scan_categories;
        ALTER TABLE scan_categories RENAME COLUMN order_id TO scan_id;
    END IF;
END $$;

-- ============================================================
-- 7. TABLE: packages
-- ============================================================

CREATE TABLE IF NOT EXISTS packages (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    price INTEGER NOT NULL DEFAULT 0,
    scan_limit INTEGER NOT NULL DEFAULT 0,
    max_members INTEGER NOT NULL DEFAULT 1,
    features TEXT[],
    is_popular BOOLEAN NOT NULL DEFAULT false,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed data paket (v5: tanpa info storage, Team tambah Dukungan prioritas)
INSERT INTO packages (id, name, price, scan_limit, max_members, features, is_popular, sort_order) VALUES
    ('free',      'Free',  0,       100,  1,  ARRAY['Scan resi barcode','100 scan/bulan','Copy resi cepat'], false, 1),
    ('basic',     'Basic', 29000,   1000, 1,  ARRAY['1000 scan/bulan','Backup & sync cloud','Export CSV','Copy resi cepat'], false, 2),
    ('pro',       'Pro',   99000,   5000, 1,  ARRAY['5000 scan/bulan','Backup & sync cloud','Export XLSX/CSV','Foto bukti scan','Statistik lengkap','Copy resi cepat'], true, 3),
    ('unlimited', 'Team',  399000,  0,    10, ARRAY['Unlimited scan/bulan','Buat & kelola tim','Hingga 10 anggota tim','Kategori wajib per scan','Backup & sync cloud','Export XLSX/CSV','Foto bukti scan','Statistik lengkap','Copy resi cepat','Dukungan prioritas'], false, 4)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    price = EXCLUDED.price,
    scan_limit = EXCLUDED.scan_limit,
    max_members = EXCLUDED.max_members,
    features = EXCLUDED.features,
    is_popular = EXCLUDED.is_popular,
    sort_order = EXCLUDED.sort_order,
    updated_at = NOW();

-- ============================================================
-- 8. ENABLE ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE scans ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE scan_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE packages ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 9. HELPER FUNCTIONS (SECURITY DEFINER — bypass RLS)
-- ============================================================

CREATE OR REPLACE FUNCTION get_my_team_ids()
RETURNS SETOF UUID
LANGUAGE SQL SECURITY DEFINER SET search_path = public
AS $$
    SELECT team_id FROM team_members WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION get_my_admin_team_ids()
RETURNS SETOF UUID
LANGUAGE SQL SECURITY DEFINER SET search_path = public
AS $$
    SELECT team_id FROM team_members WHERE user_id = auth.uid() AND role = 'admin';
$$;

CREATE OR REPLACE FUNCTION get_team_by_invite_code(code TEXT)
RETURNS TABLE (id UUID, name TEXT, invite_code TEXT, created_by UUID, created_at TIMESTAMPTZ)
LANGUAGE SQL SECURITY DEFINER SET search_path = public
AS $$
    SELECT id, name, invite_code, created_by, created_at FROM teams WHERE invite_code = code LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION get_subscription_by_email(lookup_email TEXT)
RETURNS TABLE (
    user_id UUID, email TEXT, tier TEXT, active_from TIMESTAMPTZ,
    active_until TIMESTAMPTZ, cycle_allowance INTEGER, cycle_used INTEGER,
    storage_used BIGINT, updated_at TIMESTAMPTZ
)
LANGUAGE SQL SECURITY DEFINER SET search_path = public
AS $$
    SELECT user_id, email, tier, active_from, active_until, cycle_allowance, cycle_used, storage_used, updated_at
    FROM user_subscriptions WHERE email = lookup_email LIMIT 1;
$$;

-- ============================================================
-- 10. RLS POLICIES — SCANS
-- ============================================================

DROP POLICY IF EXISTS "scans_select" ON scans;
CREATE POLICY "scans_select"
    ON scans FOR SELECT
    USING (auth.uid() = user_id OR team_id IN (SELECT get_my_team_ids()));

DROP POLICY IF EXISTS "scans_insert" ON scans;
CREATE POLICY "scans_insert"
    ON scans FOR INSERT
    WITH CHECK (auth.uid() = user_id OR team_id IN (SELECT get_my_team_ids()));

DROP POLICY IF EXISTS "scans_delete" ON scans;
CREATE POLICY "scans_delete"
    ON scans FOR DELETE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "scans_update" ON scans;
CREATE POLICY "scans_update"
    ON scans FOR UPDATE
    USING (auth.uid() = user_id OR team_id IN (SELECT get_my_team_ids()));

DROP POLICY IF EXISTS "scans_anon_select" ON scans;
CREATE POLICY "scans_anon_select"
    ON scans FOR SELECT TO anon
    USING (true);

-- ============================================================
-- 11. RLS POLICIES — TEAMS
-- ============================================================

DROP POLICY IF EXISTS "team_select" ON teams;
CREATE POLICY "team_select"
    ON teams FOR SELECT
    USING (created_by = auth.uid() OR id IN (SELECT get_my_team_ids()));

DROP POLICY IF EXISTS "team_insert" ON teams;
CREATE POLICY "team_insert"
    ON teams FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = created_by);

DROP POLICY IF EXISTS "team_update" ON teams;
CREATE POLICY "team_update"
    ON teams FOR UPDATE
    USING (id IN (SELECT get_my_admin_team_ids()));

DROP POLICY IF EXISTS "team_delete" ON teams;
CREATE POLICY "team_delete"
    ON teams FOR DELETE
    USING (id IN (SELECT get_my_admin_team_ids()));

DROP POLICY IF EXISTS "teams_anon_select" ON teams;
CREATE POLICY "teams_anon_select"
    ON teams FOR SELECT TO anon
    USING (true);

-- ============================================================
-- 12. RLS POLICIES — TEAM_MEMBERS
-- ============================================================

DROP POLICY IF EXISTS "member_select" ON team_members;
CREATE POLICY "member_select"
    ON team_members FOR SELECT
    USING (team_id IN (SELECT get_my_team_ids()));

DROP POLICY IF EXISTS "member_insert" ON team_members;
CREATE POLICY "member_insert"
    ON team_members FOR INSERT TO authenticated
    WITH CHECK (
        team_id IN (SELECT get_my_admin_team_ids())
        OR (user_id = auth.uid() AND role = 'admin' AND EXISTS (SELECT 1 FROM teams t WHERE t.id = team_id AND t.created_by = auth.uid()))
        OR (user_id = auth.uid() AND role = 'member')
    );

DROP POLICY IF EXISTS "member_update" ON team_members;
CREATE POLICY "member_update"
    ON team_members FOR UPDATE
    USING (team_id IN (SELECT get_my_admin_team_ids()));

DROP POLICY IF EXISTS "member_delete" ON team_members;
CREATE POLICY "member_delete"
    ON team_members FOR DELETE
    USING (user_id = auth.uid() OR team_id IN (SELECT get_my_admin_team_ids()));

DROP POLICY IF EXISTS "team_members_anon_select" ON team_members;
CREATE POLICY "team_members_anon_select"
    ON team_members FOR SELECT TO anon
    USING (true);

-- ============================================================
-- 13. RLS POLICIES — USER_SUBSCRIPTIONS
-- ============================================================

DROP POLICY IF EXISTS "subscription_select_own" ON user_subscriptions;
CREATE POLICY "subscription_select_own"
    ON user_subscriptions FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "subscription_insert_own" ON user_subscriptions;
CREATE POLICY "subscription_insert_own"
    ON user_subscriptions FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "subscription_update_own" ON user_subscriptions;
CREATE POLICY "subscription_update_own"
    ON user_subscriptions FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "subscription_anon_select" ON user_subscriptions;
CREATE POLICY "subscription_anon_select"
    ON user_subscriptions FOR SELECT TO anon
    USING (true);

-- ============================================================
-- 14. RLS POLICIES — CATEGORIES
-- ============================================================

DROP POLICY IF EXISTS "Users manage own categories" ON categories;
CREATE POLICY "Users manage own categories" ON categories
    FOR ALL USING (user_id = auth.uid());

-- v5: anggota tim bisa baca kategori milik admin tim mereka
DROP POLICY IF EXISTS "Team members can read admin categories" ON categories;
CREATE POLICY "Team members can read admin categories"
    ON categories FOR SELECT
    USING (
        user_id IN (
            SELECT t.created_by FROM teams t
            INNER JOIN team_members tm ON tm.team_id = t.id
            WHERE tm.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "categories_anon_select" ON categories;
CREATE POLICY "categories_anon_select"
    ON categories FOR SELECT TO anon
    USING (true);

-- ============================================================
-- 15. RLS POLICIES — SCAN_CATEGORIES
-- ============================================================

DROP POLICY IF EXISTS "Users manage own scan_categories" ON scan_categories;
CREATE POLICY "Users manage own scan_categories" ON scan_categories
    FOR ALL USING (
        category_id IN (SELECT id FROM categories WHERE user_id = auth.uid())
        OR category_id IN (
            SELECT c.id FROM categories c
            INNER JOIN teams t ON t.created_by = c.user_id
            INNER JOIN team_members tm ON tm.team_id = t.id
            WHERE tm.user_id = auth.uid()
        )
    );

-- v5: anggota tim bisa baca scan_categories untuk scan yang ada di tim mereka
DROP POLICY IF EXISTS "Team members can read team scan_categories" ON scan_categories;
CREATE POLICY "Team members can read team scan_categories"
    ON scan_categories FOR SELECT
    USING (
        scan_id IN (
            SELECT id FROM scans WHERE team_id IN (SELECT get_my_team_ids())
        )
    );

-- v5: team members can insert scan_categories for scans in their team
DROP POLICY IF EXISTS "Team members can insert team scan_categories" ON scan_categories;
CREATE POLICY "Team members can insert team scan_categories"
    ON scan_categories FOR INSERT
    WITH CHECK (
        scan_id IN (
            SELECT id FROM scans WHERE team_id IN (SELECT get_my_team_ids())
        )
    );

-- v5: team admin can insert scan_categories for their team scans
DROP POLICY IF EXISTS "Team admin can insert team scan_categories" ON scan_categories;
CREATE POLICY "Team admin can insert team scan_categories"
    ON scan_categories FOR INSERT
    WITH CHECK (
        scan_id IN (
            SELECT id FROM scans WHERE team_id IN (
                SELECT id FROM teams WHERE created_by = auth.uid()
            )
        )
    );

DROP POLICY IF EXISTS "scan_categories_anon_select" ON scan_categories;
CREATE POLICY "scan_categories_anon_select"
    ON scan_categories FOR SELECT TO anon
    USING (true);

-- ============================================================
-- 16. RLS POLICIES — PACKAGES
-- ============================================================

DROP POLICY IF EXISTS "packages_select_all" ON packages;
CREATE POLICY "packages_select_all"
    ON packages FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "packages_anon_select" ON packages;
CREATE POLICY "packages_anon_select"
    ON packages FOR SELECT TO anon
    USING (true);

-- ============================================================
-- 17. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_scans_user_id ON scans(user_id);
CREATE INDEX IF NOT EXISTS idx_scans_team_id ON scans(team_id);
CREATE INDEX IF NOT EXISTS idx_scans_resi ON scans(resi);
CREATE UNIQUE INDEX IF NOT EXISTS idx_scans_team_resi_unique ON scans(team_id, resi);
CREATE UNIQUE INDEX IF NOT EXISTS idx_scans_user_resi_unique ON scans(user_id, resi);
CREATE INDEX IF NOT EXISTS idx_scans_date ON scans(date);
CREATE INDEX IF NOT EXISTS idx_scans_device_id ON scans(device_id);
CREATE INDEX IF NOT EXISTS idx_team_members_user_id ON team_members(user_id);
CREATE INDEX IF NOT EXISTS idx_team_members_team_id ON team_members(team_id);
CREATE INDEX IF NOT EXISTS idx_teams_invite_code ON teams(invite_code);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_email ON user_subscriptions(email);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_updated_at ON user_subscriptions(updated_at);
CREATE INDEX IF NOT EXISTS idx_categories_user ON categories(user_id);
CREATE INDEX IF NOT EXISTS idx_sc_order ON scan_categories(scan_id);
CREATE INDEX IF NOT EXISTS idx_sc_category ON scan_categories(category_id);

-- ============================================================
-- 18. TABLE: contact_messages
-- ============================================================

CREATE TABLE IF NOT EXISTS contact_messages (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    message TEXT NOT NULL,
    sent_via_email BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE contact_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read contact_messages" ON contact_messages;
CREATE POLICY "Allow read contact_messages" ON contact_messages
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow insert contact_messages" ON contact_messages;
CREATE POLICY "Allow insert contact_messages" ON contact_messages
    FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "No update delete contact_messages" ON contact_messages;
CREATE POLICY "No update delete contact_messages" ON contact_messages
    FOR UPDATE USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS "No delete contact_messages" ON contact_messages;
CREATE POLICY "No delete contact_messages" ON contact_messages
    FOR DELETE USING (false);

-- ============================================================
-- 19. MIGRASI DATA: backfill team_id pada scans lama
-- Jalankan ini jika sudah ada data scan sebelum kolom team_id ditambahkan
-- ============================================================

-- Update team_id untuk semua scan milik anggota tim yang belum punya team_id
UPDATE scans s
SET team_id = tm.team_id
FROM team_members tm
WHERE s.user_id = tm.user_id::text::uuid
  AND s.team_id IS NULL;

-- ============================================================
-- SELESAI v5 — semua tabel, RLS, policies, indexes, seed data,
-- contact_messages, dan migrasi team_id
-- ============================================================

-- ============================================================
-- 20. CLEANUP: Hapus storage foto saat user dihapus
-- Supabase Storage tidak mendukung ON DELETE CASCADE,
-- jadi perlu trigger untuk hapus folder foto user dari bucket
-- ============================================================

CREATE OR REPLACE FUNCTION delete_user_storage()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    folder_path TEXT;
BEGIN
    -- Hapus folder foto user dari bucket scan-photos
    -- Supabase storage API tidak bisa dipanggil dari SQL,
    -- jadi kita hapus referensi photo_url dari scans yang di-CASCADE
    -- Storage cleanup harus dilakukan via Edge Function atau app logic
    NULL;
END;
$$;

-- Catatan: Supabase Storage tidak bisa diakses dari SQL trigger.
-- Cleanup storage harus dilakukan melalui:
-- 1. Edge Function yang dipanggil saat user delete
-- 2. Atau app-side cleanup sebelum memanggil admin.deleteUser()

-- ============================================================
-- 21. FUNCTION: Hapus semua data user (dipanggil dari app)
-- Termasuk hapus folder storage via app-side sebelum delete akun
-- ============================================================

CREATE OR REPLACE FUNCTION cleanup_user_data(target_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Hapus scan_categories untuk scans milik user
    DELETE FROM scan_categories WHERE scan_id IN (SELECT id FROM scans WHERE user_id = target_user_id);
    -- Hapus scans milik user
    DELETE FROM scans WHERE user_id = target_user_id;
    -- Hapus categories milik user
    DELETE FROM categories WHERE user_id = target_user_id;
    -- Hapus team_members
    DELETE FROM team_members WHERE user_id = target_user_id;
    -- Hapus user_subscriptions
    DELETE FROM user_subscriptions WHERE user_id = target_user_id;
    -- Jika user adalah admin tim, bubarkan tim
    DELETE FROM team_members WHERE team_id IN (SELECT id FROM teams WHERE created_by = target_user_id);
    DELETE FROM teams WHERE created_by = target_user_id;
END;
$$;
