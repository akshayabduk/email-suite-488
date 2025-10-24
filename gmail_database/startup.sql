-- Gmail Clone PostgreSQL Schema
-- Schema: users, emails, labels, email_labels (junction), attachments, optional refresh_tokens
-- Includes indexes and minimal seed data

BEGIN;

-- USERS
CREATE TABLE IF NOT EXISTS users (
    id            BIGSERIAL PRIMARY KEY,
    email         VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name  VARCHAR(255),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- EMAILS
CREATE TABLE IF NOT EXISTS emails (
    id               BIGSERIAL PRIMARY KEY,
    thread_id        BIGINT, -- future support for threading
    from_user_id     BIGINT REFERENCES users(id) ON DELETE SET NULL,
    to_recipients    TEXT NOT NULL,    -- comma-separated emails (normalize later if needed)
    cc_recipients    TEXT,             -- optional
    bcc_recipients   TEXT,             -- optional
    subject          TEXT,
    body_plain       TEXT,
    body_html        TEXT,
    is_read          BOOLEAN NOT NULL DEFAULT FALSE,
    is_starred       BOOLEAN NOT NULL DEFAULT FALSE,
    is_archived      BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted       BOOLEAN NOT NULL DEFAULT FALSE,
    sent_at          TIMESTAMPTZ,      -- when actually sent
    received_at      TIMESTAMPTZ,      -- when received (for inbound)
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_emails_from_user_id ON emails(from_user_id);
CREATE INDEX IF NOT EXISTS idx_emails_sent_at ON emails(sent_at);
CREATE INDEX IF NOT EXISTS idx_emails_received_at ON emails(received_at);
CREATE INDEX IF NOT EXISTS idx_emails_is_read ON emails(is_read);
CREATE INDEX IF NOT EXISTS idx_emails_is_archived ON emails(is_archived);

-- LABELS
CREATE TABLE IF NOT EXISTS labels (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT REFERENCES users(id) ON DELETE CASCADE,
    name        VARCHAR(100) NOT NULL,
    color       VARCHAR(20),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, name)
);

CREATE INDEX IF NOT EXISTS idx_labels_user_id ON labels(user_id);

-- EMAIL_LABELS (junction)
CREATE TABLE IF NOT EXISTS email_labels (
    email_id BIGINT REFERENCES emails(id) ON DELETE CASCADE,
    label_id BIGINT REFERENCES labels(id) ON DELETE CASCADE,
    PRIMARY KEY (email_id, label_id)
);

CREATE INDEX IF NOT EXISTS idx_email_labels_label_id ON email_labels(label_id);

-- ATTACHMENTS
CREATE TABLE IF NOT EXISTS attachments (
    id            BIGSERIAL PRIMARY KEY,
    email_id      BIGINT REFERENCES emails(id) ON DELETE CASCADE,
    filename      TEXT NOT NULL,
    mime_type     TEXT,
    size_bytes    BIGINT,
    storage_path  TEXT,          -- file system path or object storage key
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_attachments_email_id ON attachments(email_id);

-- OPTIONAL: REFRESH TOKENS (for sessions)
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT REFERENCES users(id) ON DELETE CASCADE,
    token_hash    TEXT NOT NULL,               -- store only a hash
    expires_at    TIMESTAMPTZ NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_at ON refresh_tokens(expires_at);

-- TRIGGERS: update updated_at on rows
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_users_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_users_set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_emails_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_emails_set_updated_at
    BEFORE UPDATE ON emails
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
END$$;

-- Minimal seed data
-- Password hashes are placeholders (e.g., bcrypt of 'password'); replace when wiring auth
INSERT INTO users (email, password_hash, display_name)
VALUES 
  ('alice@example.com', '$2b$10$examplehash_alice_password', 'Alice A.'),
  ('bob@example.com',   '$2b$10$examplehash_bob_password',   'Bob B.')
ON CONFLICT (email) DO NOTHING;

-- Default labels per user
WITH u AS (
  SELECT id AS user_id, email FROM users
)
INSERT INTO labels (user_id, name, color)
SELECT user_id, lbl, col
FROM (
  SELECT user_id, 'Inbox'::varchar(100) AS lbl, '#2563EB'::varchar(20) AS col FROM u
  UNION ALL
  SELECT user_id, 'Starred', '#F59E0B' FROM u
  UNION ALL
  SELECT user_id, 'Sent',    '#10B981' FROM u
  UNION ALL
  SELECT user_id, 'Drafts',  '#6B7280' FROM u
) t
ON CONFLICT (user_id, name) DO NOTHING;

-- Sample email
WITH alice AS (
  SELECT id FROM users WHERE email = 'alice@example.com' LIMIT 1
), bob AS (
  SELECT id FROM users WHERE email = 'bob@example.com' LIMIT 1
)
INSERT INTO emails (from_user_id, to_recipients, subject, body_plain, body_html, is_read, is_starred, sent_at, received_at)
SELECT a.id, 'bob@example.com', 'Welcome to Gmail Clone', 
       'Hi Bob, welcome to the Gmail clone project!', 
       '<p>Hi <b>Bob</b>, welcome to the Gmail clone project!</p>',
       FALSE, TRUE, NOW(), NOW()
FROM alice a
ON CONFLICT DO NOTHING;

-- Attach a label to the sample email
WITH e AS (
  SELECT id FROM emails ORDER BY id DESC LIMIT 1
), b AS (
  SELECT id FROM labels WHERE name = 'Inbox' ORDER BY id ASC LIMIT 1
)
INSERT INTO email_labels (email_id, label_id)
SELECT e.id, b.id FROM e, b
ON CONFLICT DO NOTHING;

COMMIT;
