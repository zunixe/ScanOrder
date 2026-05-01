-- Table untuk menyimpan pesan kontak sebagai fallback email
CREATE TABLE IF NOT EXISTS contact_messages (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  message TEXT NOT NULL,
  sent_via_email BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS (hanya admin bisa baca via service key)
ALTER TABLE contact_messages ENABLE ROW LEVEL SECURITY;

-- Nobody can read via anon key (only service role / admin)
CREATE POLICY "No public access" ON contact_messages
  FOR ALL USING (false) WITH CHECK (false);
