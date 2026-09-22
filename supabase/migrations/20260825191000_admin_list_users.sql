-- ============================================================
-- RPC admin_list_users() — daftar user terdaftar untuk Admin Panel.
-- Guard: is_super_admin(). Dipanggil dari lib/admin/users_list_screen.dart.
--
-- Return per user: id, email, tanggal daftar, jumlah scan, scan terakhir,
-- tier langganan (null = belum pernah punya baris user_subscriptions).
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_list_users()
RETURNS TABLE(
    user_id uuid,
    email text,
    created_at timestamptz,
    total_scans bigint,
    last_scan_at bigint,
    tier text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'FORBIDDEN: bukan super admin';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u.email,
    u.created_at,
    count(s.id)                       AS total_scans,
    max(s.scanned_at)                 AS last_scan_at,
    max(us.tier)                      AS tier
  FROM auth.users u
  LEFT JOIN scans s ON s.user_id = u.id
  LEFT JOIN user_subscriptions us ON us.user_id = u.id
  GROUP BY u.id, u.email, u.created_at
  ORDER BY u.created_at DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_list_users() FROM anon;
GRANT  EXECUTE ON FUNCTION public.admin_list_users() TO authenticated;
