-- ============================================================
-- SUPABASE FULL SETUP (v4 — dari awal, tabel renamed)
-- Jalankan semua query ini di Supabase Dashboard → SQL Editor
-- Tabel: orders→scans, order_categories→scan_categories
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
    team_id UUID REFERENCES teams(id) ON DELETE SET NULL
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

-- Seed data paket
INSERT INTO packages (id, name, price, scan_limit, max_members, features, is_popular, sort_order) VALUES
    ('free',      'Free',  0,       100, 1,  ARRAY['Scan resi dasar','100 scan/bulan','1 perangkat','100MB penyimpanan'], false, 1),
    ('basic',     'Basic', 29000,   1000, 1,  ARRAY['1000 scan/bulan','1 perangkat','2GB penyimpanan','Export CSV'], false, 2),
    ('pro',       'Pro',   99000,   5000, 1,  ARRAY['5000 scan/bulan','1 perangkat','10GB penyimpanan','Export CSV & Excel','Foto bukti scan','Dukungan prioritas'], true, 3),
    ('unlimited', 'Team',  399000,  0,   10, ARRAY['Scan unlimited','Hingga 10 anggota tim','Dashboard tim','Kategori order','Laporan tim','Penyimpanan unlimited'], false, 4)
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
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "scans_delete" ON scans;
CREATE POLICY "scans_delete"
    ON scans FOR DELETE
    USING (auth.uid() = user_id);

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
-- SELESAI — semua tabel, RLS, policies, indexes, dan seed data
-- ============================================================
