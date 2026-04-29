-- ============================================================
-- SUPABASE TEAM SETUP (CORRECTED)
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

-- 6. RLS Policies — TEAMS
DROP POLICY IF EXISTS "team_select" ON teams;
CREATE POLICY "team_select"
    ON teams FOR SELECT
    USING (id IN (
        SELECT team_id FROM team_members WHERE user_id = auth.uid()
    ));

DROP POLICY IF EXISTS "team_insert" ON teams;
CREATE POLICY "team_insert"
    ON teams FOR INSERT
    WITH CHECK (auth.uid() = created_by);

DROP POLICY IF EXISTS "team_update" ON teams;
CREATE POLICY "team_update"
    ON teams FOR UPDATE
    USING (id IN (
        SELECT team_id FROM team_members WHERE user_id = auth.uid() AND role = 'admin'
    ));

DROP POLICY IF EXISTS "team_delete" ON teams;
CREATE POLICY "team_delete"
    ON teams FOR DELETE
    USING (id IN (
        SELECT team_id FROM team_members WHERE user_id = auth.uid() AND role = 'admin'
    ));

-- 7. RLS Policies — TEAM_MEMBERS
DROP POLICY IF EXISTS "member_select" ON team_members;
CREATE POLICY "member_select"
    ON team_members FOR SELECT
    USING (team_id IN (
        SELECT team_id FROM team_members WHERE user_id = auth.uid()
    ));

DROP POLICY IF EXISTS "member_insert" ON team_members;
CREATE POLICY "member_insert"
    ON team_members FOR INSERT
    WITH CHECK (team_id IN (
        SELECT team_id FROM team_members WHERE user_id = auth.uid() AND role = 'admin'
    ));

-- 8. RLS Policies — ORDERS (update yang lama)
DROP POLICY IF EXISTS "orders_select" ON orders;
CREATE POLICY "orders_select"
    ON orders FOR SELECT
    USING (
        auth.uid() = user_id
        OR team_id IN (
            SELECT team_id FROM team_members WHERE user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "orders_insert" ON orders;
CREATE POLICY "orders_insert"
    ON orders FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "orders_delete" ON orders;
CREATE POLICY "orders_delete"
    ON orders FOR DELETE
    USING (auth.uid() = user_id);

-- 9. Index untuk performa
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_team_id ON orders(team_id);
CREATE INDEX IF NOT EXISTS idx_team_members_user_id ON team_members(user_id);
CREATE INDEX IF NOT EXISTS idx_team_members_team_id ON team_members(team_id);
CREATE INDEX IF NOT EXISTS idx_teams_invite_code ON teams(invite_code);
