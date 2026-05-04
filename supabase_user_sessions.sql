-- Single-device login constraint for team users (pro, basic)
-- Run this in Supabase SQL Editor

-- 1. Create user_sessions table
CREATE TABLE IF NOT EXISTS public.user_sessions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  last_heartbeat TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. One active session per user (only latest is valid)
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_sessions_one_per_user
  ON public.user_sessions (user_id);

-- 3. Enable RLS
ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;

-- 4. RLS: users can only read/write their own session
CREATE POLICY "Users can manage own session"
  ON public.user_sessions
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- 5. Auto-cleanup stale sessions (older than 10 minutes without heartbeat)
-- Run periodically via pg_cron or manually
-- SELECT pg_cron.schedule('cleanup-stale-sessions', '*/5 * * * *', $$DELETE FROM public.user_sessions WHERE last_heartbeat < now() - interval '10 minutes'$$);
