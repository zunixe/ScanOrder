-- ============================================================
-- SUPABASE TEAM SETUP (v3 — fixed infinite recursion)
-- Jalankan semua query ini di Supabase Dashboard → SQL Editor
-- ============================================================

-- 1. Tambah kolom user_id ke orders kalau belum ada
ALTER TABLE orders ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);

-- 2. Table: teams
CREATE TABLE IF NOT EXISTS teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    invite_code TEXT NOT NULL UNIQUE,
    created_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Table: team_members
CREATE TABLE IF NOT EXISTS team_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member',
    email TEXT,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(team_id, user_id)
);

-- 4. Tambah team_id ke orders
ALTER TABLE orders ADD COLUMN IF NOT EXISTS team_id UUID REFERENCES teams(id) ON DELETE SET NULL;

-- 5. Enable RLS
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_members ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 6. Helper functions (SECURITY DEFINER) to avoid RLS recursion
--    These bypass RLS when called from policies, preventing
--    infinite recursion on self-referencing table policies.
-- ============================================================

-- Get team IDs where current user is a member
CREATE OR REPLACE FUNCTION get_my_team_ids()
RETURNS SETOF UUID
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT team_id FROM team_members WHERE user_id = auth.uid();
$$;

-- Get team IDs where current user is an admin
CREATE OR REPLACE FUNCTION get_my_admin_team_ids()
RETURNS SETOF UUID
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT team_id FROM team_members WHERE user_id = auth.uid() AND role = 'admin';
$$;

-- Lookup team by invite code (bypass RLS so non-members can join)
CREATE OR REPLACE FUNCTION get_team_by_invite_code(code TEXT)
RETURNS TABLE (
    id UUID,
    name TEXT,
    invite_code TEXT,
    created_by UUID,
    created_at TIMESTAMPTZ
)
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT id, name, invite_code, created_by, created_at
    FROM teams
    WHERE invite_code = code
    LIMIT 1;
$$;

-- ============================================================
-- 7. RLS Policies — TEAMS (use helper functions)
-- ============================================================

DROP POLICY IF EXISTS "team_select" ON teams;
CREATE POLICY "team_select"
    ON teams FOR SELECT
    USING (
        created_by = auth.uid()
        OR id IN (SELECT get_my_team_ids())
    );

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

-- ============================================================
-- 8. RLS Policies — TEAM_MEMBERS (use helper functions)
-- ============================================================

DROP POLICY IF EXISTS "member_select" ON team_members;
CREATE POLICY "member_select"
    ON team_members FOR SELECT
    USING (team_id IN (SELECT get_my_team_ids()));

DROP POLICY IF EXISTS "member_insert" ON team_members;
CREATE POLICY "member_insert"
    ON team_members FOR INSERT TO authenticated
    WITH CHECK (
        -- Admin bisa tambah siapa saja ke timnya
        team_id IN (SELECT get_my_admin_team_ids())
        OR
        -- Creator bisa insert dirinya sebagai admin saat buat tim
        (
            user_id = auth.uid()
            AND role = 'admin'
            AND EXISTS (
                SELECT 1 FROM teams t
                WHERE t.id = team_id AND t.created_by = auth.uid()
            )
        )
        OR
        -- User bisa join sendiri sebagai member (via invite code)
        (
            user_id = auth.uid()
            AND role = 'member'
        )
    );

DROP POLICY IF EXISTS "member_update" ON team_members;
CREATE POLICY "member_update"
    ON team_members FOR UPDATE
    USING (team_id IN (SELECT get_my_admin_team_ids()));

DROP POLICY IF EXISTS "member_delete" ON team_members;
CREATE POLICY "member_delete"
    ON team_members FOR DELETE
    USING (
        user_id = auth.uid()
        OR team_id IN (SELECT get_my_admin_team_ids())
    );

-- ============================================================
-- 9. RLS Policies — ORDERS
-- ============================================================

DROP POLICY IF EXISTS "orders_select" ON orders;
CREATE POLICY "orders_select"
    ON orders FOR SELECT
    USING (
        auth.uid() = user_id
        OR team_id IN (SELECT get_my_team_ids())
    );

DROP POLICY IF EXISTS "orders_insert" ON orders;
CREATE POLICY "orders_insert"
    ON orders FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "orders_delete" ON orders;
CREATE POLICY "orders_delete"
    ON orders FOR DELETE
    USING (auth.uid() = user_id);

-- 10. Index untuk performa
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_team_id ON orders(team_id);
CREATE INDEX IF NOT EXISTS idx_team_members_user_id ON team_members(user_id);
CREATE INDEX IF NOT EXISTS idx_team_members_team_id ON team_members(team_id);
CREATE INDEX IF NOT EXISTS idx_teams_invite_code ON teams(invite_code);

-- ============================================================
-- 11. Table: user_subscriptions (sync state langganan per user)
-- ============================================================

CREATE TABLE IF NOT EXISTS user_subscriptions (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    tier TEXT NOT NULL DEFAULT 'free',
    active_from TIMESTAMPTZ,
    active_until TIMESTAMPTZ,
    cycle_allowance INTEGER NOT NULL DEFAULT 10,
    cycle_used INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE user_subscriptions ENABLE ROW LEVEL SECURITY;

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

CREATE INDEX IF NOT EXISTS idx_user_subscriptions_updated_at ON user_subscriptions(updated_at);

-- Tambah kolom email jika tabel sudah ada tanpa kolom ini
ALTER TABLE user_subscriptions ADD COLUMN IF NOT EXISTS email TEXT;

-- Tambah kolom storage_used untuk tracking penyimpanan per user
ALTER TABLE user_subscriptions ADD COLUMN IF NOT EXISTS storage_used BIGINT NOT NULL DEFAULT 0;

-- Index untuk lookup by email (Google login sync)
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_email ON user_subscriptions(email);

-- ============================================================
-- 12. Helper function: lookup subscription by email
--     (SECURITY DEFINER untuk bypass RLS saat Google login)
-- ============================================================

CREATE OR REPLACE FUNCTION get_subscription_by_email(lookup_email TEXT)
RETURNS TABLE (
    user_id UUID,
    email TEXT,
    tier TEXT,
    active_from TIMESTAMPTZ,
    active_until TIMESTAMPTZ,
    cycle_allowance INTEGER,
    cycle_used INTEGER,
    storage_used BIGINT,
    updated_at TIMESTAMPTZ
)
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT user_id, email, tier, active_from, active_until, cycle_allowance, cycle_used, storage_used, updated_at
    FROM user_subscriptions
    WHERE email = lookup_email
    LIMIT 1;
$$;

-- ============================================================
-- Categories & Order-Categories (Team tier feature)
-- ============================================================

CREATE TABLE IF NOT EXISTS categories (
    id BIGINT PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_categories (
    id BIGINT PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id) ON DELETE CASCADE,
    category_id BIGINT REFERENCES categories(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(order_id, category_id)
);

CREATE INDEX IF NOT EXISTS idx_categories_user ON categories(user_id);
CREATE INDEX IF NOT EXISTS idx_oc_order ON order_categories(order_id);
CREATE INDEX IF NOT EXISTS idx_oc_category ON order_categories(category_id);

-- RLS for categories
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users manage own categories" ON categories;
CREATE POLICY "Users manage own categories" ON categories
    FOR ALL USING (user_id = auth.uid());

-- RLS for order_categories
ALTER TABLE order_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users manage own order_categories" ON order_categories;
CREATE POLICY "Users manage own order_categories" ON order_categories
    FOR ALL USING (
        category_id IN (SELECT id FROM categories WHERE user_id = auth.uid())
    );

-- ============================================================
-- DASHBOARD ANON READ POLICIES (read-only for admin dashboard)
--    Dashboard uses anon key without auth, so we need
--    separate SELECT policies for the anon role.
--    Only SELECT is allowed — no INSERT/UPDATE/DELETE.
-- ============================================================

-- Orders: anon can read all
DROP POLICY IF EXISTS "orders_anon_select" ON orders;
CREATE POLICY "orders_anon_select"
    ON orders FOR SELECT TO anon
    USING (true);

-- user_subscriptions: anon can read all
DROP POLICY IF EXISTS "subscription_anon_select" ON user_subscriptions;
CREATE POLICY "subscription_anon_select"
    ON user_subscriptions FOR SELECT TO anon
    USING (true);

-- teams: anon can read all
DROP POLICY IF EXISTS "teams_anon_select" ON teams;
CREATE POLICY "teams_anon_select"
    ON teams FOR SELECT TO anon
    USING (true);

-- team_members: anon can read all
DROP POLICY IF EXISTS "team_members_anon_select" ON team_members;
CREATE POLICY "team_members_anon_select"
    ON team_members FOR SELECT TO anon
    USING (true);

-- categories: anon can read all
DROP POLICY IF EXISTS "categories_anon_select" ON categories;
CREATE POLICY "categories_anon_select"
    ON categories FOR SELECT TO anon
    USING (true);

-- order_categories: anon can read all
DROP POLICY IF EXISTS "order_categories_anon_select" ON order_categories;
CREATE POLICY "order_categories_anon_select"
    ON order_categories FOR SELECT TO anon
    USING (true);

-- ============================================================
-- PACKAGES: Master table untuk paket/langganan
-- ============================================================

CREATE TABLE IF NOT EXISTS packages (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    price INTEGER NOT NULL DEFAULT 0,       -- harga per bulan dalam Rupiah
    scan_limit INTEGER NOT NULL DEFAULT 0,   -- 0 = unlimited
    max_members INTEGER NOT NULL DEFAULT 1,  -- 1 = personal, >1 = team
    features TEXT[],                         -- array fitur
    is_popular BOOLEAN NOT NULL DEFAULT false,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed data paket (sesuai ScanOrder Flutter: quota_service.dart)
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

-- RLS for packages
ALTER TABLE packages ENABLE ROW LEVEL SECURITY;

-- Semua user bisa baca paket (untuk halaman pricing)
DROP POLICY IF EXISTS "packages_select_all" ON packages;
CREATE POLICY "packages_select_all"
    ON packages FOR SELECT
    USING (true);

-- packages: anon can read all
DROP POLICY IF EXISTS "packages_anon_select" ON packages;
CREATE POLICY "packages_anon_select"
    ON packages FOR SELECT TO anon
    USING (true);
