-- Login history with geolocation for each user
-- Run this in Supabase SQL Editor

-- 1. Create login_history table
CREATE TABLE IF NOT EXISTS public.login_history (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  device_id TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  city TEXT,
  region TEXT,
  country TEXT,
  ip_address TEXT,
  login_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Enable RLS
ALTER TABLE public.login_history ENABLE ROW LEVEL SECURITY;

-- 3. RLS: users can only read their own login history
CREATE POLICY "Users can read own login history"
  ON public.public.login_history
  FOR SELECT
  USING (auth.uid() = user_id);

-- 4. RLS: users can insert their own login history
CREATE POLICY "Users can insert own login history"
  ON public.login_history
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- 5. Index for fast lookup
CREATE INDEX IF NOT EXISTS idx_login_history_user_id
  ON public.login_history (user_id, login_at DESC);
