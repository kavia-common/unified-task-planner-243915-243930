-- 001c - tags + tasks + notes + attachments
\set ON_ERROR_STOP on

-- Tags
CREATE TABLE IF NOT EXISTS tag (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    name text NOT NULL,
    color text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, name)
);

CREATE INDEX IF NOT EXISTS idx_tag_user_id ON tag(user_id);

-- Enums
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_status') THEN
        CREATE TYPE task_status AS ENUM ('todo', 'in_progress', 'done', 'archived');
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_priority') THEN
        CREATE TYPE task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
    END IF;
END$$;

-- Tasks
CREATE TABLE IF NOT EXISTS task (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    list_id uuid REFERENCES task_list(id) ON DELETE SET NULL,

    title text NOT NULL,
    description text,

    status task_status NOT NULL DEFAULT 'todo',
    priority task_priority NOT NULL DEFAULT 'medium',

    due_at timestamptz,
    start_at timestamptz,

    sort_order integer NOT NULL DEFAULT 0,
    completed_at timestamptz,

    -- FK added in 001d after recurring_rule exists
    recurring_rule_id uuid,

    deleted_at timestamptz,

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT task_completed_requires_done CHECK (
        (completed_at IS NULL) OR (status IN ('done', 'archived'))
    )
);

CREATE INDEX IF NOT EXISTS idx_task_user_id ON task(user_id);
CREATE INDEX IF NOT EXISTS idx_task_list_id ON task(list_id);
CREATE INDEX IF NOT EXISTS idx_task_user_status ON task(user_id, status);
CREATE INDEX IF NOT EXISTS idx_task_user_priority ON task(user_id, priority);
CREATE INDEX IF NOT EXISTS idx_task_user_due_at ON task(user_id, due_at);
CREATE INDEX IF NOT EXISTS idx_task_user_deleted_at ON task(user_id, deleted_at);

-- Search index (simple English tsvector)
CREATE INDEX IF NOT EXISTS idx_task_search_tsv ON task
USING GIN (to_tsvector('english', coalesce(title,'') || ' ' || coalesce(description,'')));

-- Task<->Tag mapping
CREATE TABLE IF NOT EXISTS task_tag (
    task_id uuid NOT NULL REFERENCES task(id) ON DELETE CASCADE,
    tag_id uuid NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (task_id, tag_id)
);

CREATE INDEX IF NOT EXISTS idx_task_tag_tag_id ON task_tag(tag_id);

-- Notes
CREATE TABLE IF NOT EXISTS task_note (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id uuid NOT NULL REFERENCES task(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    content text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_task_note_task_id ON task_note(task_id);
CREATE INDEX IF NOT EXISTS idx_task_note_user_id ON task_note(user_id);

-- Attachment metadata only (file bytes stored elsewhere)
CREATE TABLE IF NOT EXISTS task_attachment (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id uuid NOT NULL REFERENCES task(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,

    file_name text NOT NULL,
    content_type text,
    byte_size bigint,

    storage_provider text NOT NULL DEFAULT 'local',
    storage_key text NOT NULL,

    checksum_sha256 text,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_task_attachment_task_id ON task_attachment(task_id);
CREATE INDEX IF NOT EXISTS idx_task_attachment_user_id ON task_attachment(user_id);
CREATE INDEX IF NOT EXISTS idx_task_attachment_storage_key ON task_attachment(storage_provider, storage_key);
