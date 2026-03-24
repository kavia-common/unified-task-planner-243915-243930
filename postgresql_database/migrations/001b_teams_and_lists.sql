-- 001b - teams + shared/personal lists
\set ON_ERROR_STOP on

CREATE TABLE IF NOT EXISTS team (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_by_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (created_by_user_id, name)
);

CREATE TABLE IF NOT EXISTS team_member (
    team_id uuid NOT NULL REFERENCES team(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    role text NOT NULL DEFAULT 'member', -- 'owner' | 'admin' | 'member'
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (team_id, user_id)
);

CREATE TABLE IF NOT EXISTS task_list (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id uuid REFERENCES app_user(id) ON DELETE CASCADE,
    team_id uuid REFERENCES team(id) ON DELETE CASCADE,
    name text NOT NULL,
    color text,
    sort_order integer NOT NULL DEFAULT 0,
    is_archived boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT task_list_owner_xor_team CHECK (
        (owner_user_id IS NOT NULL AND team_id IS NULL) OR
        (owner_user_id IS NULL AND team_id IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_task_list_owner_user_id ON task_list(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_task_list_team_id ON task_list(team_id);
