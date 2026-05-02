-- Table untuk menyimpan pesan kontak sebagai fallback email
CREATE TABLE IF NOT EXISTS contact_messages (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  message TEXT NOT NULL,
  sent_via_email BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE contact_messages ENABLE ROW LEVEL SECURITY;

-- Allow reading (admin dashboard uses anon key + login guard)
CREATE POLICY "Allow read contact_messages" ON contact_messages
  FOR SELECT USING (true);

-- Allow insert from edge function (anon key)
CREATE POLICY "Allow insert contact_messages" ON contact_messages
  FOR INSERT WITH CHECK (true);

-- Prevent update/delete via anon key
CREATE POLICY "No update delete contact_messages" ON contact_messages
  FOR UPDATE USING (false) WITH CHECK (false);
CREATE POLICY "No delete contact_messages" ON contact_messages
  FOR DELETE USING (false);
