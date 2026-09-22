-- ============================================================
-- FIX: is_super_admin() harus selalu RETURN boolean ketat.
--
-- Versi lama: coalesce(auth.email()) = 'email'
-- → di sesi tanpa JWT, auth.email() = NULL → perbandingan = NULL
-- → fungsi return NULL → "IF NOT <null>" TIDAK me-raise
--   (guard bocor utk koneksi non-user seperti service role).
--
-- Perbaikan: coalesce(perbandingan, false) → selalu true/false.
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(auth.email() = 'zunixe@gmail.com', false);
$$;

REVOKE EXECUTE ON FUNCTION public.is_super_admin() FROM anon;
GRANT  EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;
