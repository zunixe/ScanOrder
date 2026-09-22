-- ============================================================
-- RLS Policies untuk fitur Tim
-- Jalankan di Supabase Dashboard → SQL Editor
-- ============================================================

-- 1. Tambah kolom team_id di tabel scans (jika belum ada)
ALTER TABLE scans ADD COLUMN IF NOT EXISTS team_id TEXT;
CREATE INDEX IF NOT EXISTS idx_scans_team_id ON scans(team_id);

-- 2. Allow team members to read ALL scans in their team (termasuk scan admin & anggota lain)
CREATE POLICY "Team members can read team scans"
ON scans FOR SELECT
USING (
  team_id IN (
    SELECT tm.team_id FROM team_members tm
    WHERE tm.user_id = auth.uid()
  )
);

-- 3. Allow team members to read categories created by their team admin
CREATE POLICY "Team members can read admin categories"
ON categories FOR SELECT
USING (
  user_id IN (
    SELECT t.created_by FROM teams t
    INNER JOIN team_members tm ON tm.team_id = t.id
    WHERE tm.user_id = auth.uid()
  )
);

-- 4. Verifikasi policy sudah terdaftar
SELECT schemaname, tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('scans', 'categories')
ORDER BY tablename, policyname;
