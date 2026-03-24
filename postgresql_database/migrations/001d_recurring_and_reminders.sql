-- 001d - recurring + reminders/notifications
\set ON_ERROR_STOP on

-- Recurrence enums
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'recurrence_freq') THEN
        CREATE TYPE recurrence_freq AS ENUM ('daily', 'weekly', 'monthly', 'yearly');
    END IF;
END$$;

-- Recurring rules
CREATE TABLE IF NOT EXISTS recurring_rule (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,

    freq recurrence_freq NOT NULL,
    interval integer NOT NULL DEFAULT 1 CHECK (interval >= 1),
    by_weekday smallint[],

    until_at timestamptz,
    count integer CHECK (count IS NULL OR count >= 1),

    timezone text NOT NULL DEFAULT 'UTC',

    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_recurring_rule_user_id ON recurring_rule(user_id);

-- Attach FK from task.recurring_rule_id to recurring_rule.id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'task_recurring_rule_id_fkey'
    ) THEN
        ALTER TABLE task
            ADD CONSTRAINT task_recurring_rule_id_fkey
            FOREIGN KEY (recurring_rule_id) REFERENCES recurring_rule(id) ON DELETE SET NULL;
    END IF;
END$$;

-- Optional: materialized occurrences (useful for calendar view)
CREATE TABLE IF NOT EXISTS task_occurrence (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id uuid NOT NULL REFERENCES task(id) ON DELETE CASCADE,
    occurrence_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (task_id, occurrence_at)
);

CREATE INDEX IF NOT EXISTS idx_task_occurrence_task_id ON task_occurrence(task_id);
CREATE INDEX IF NOT EXISTS idx_task_occurrence_occurrence_at ON task_occurrence(occurrence_at);

-- Reminders enums
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'reminder_channel') THEN
        CREATE TYPE reminder_channel AS ENUM ('in_app', 'email');
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'reminder_status') THEN
        CREATE TYPE reminder_status AS ENUM ('scheduled', 'sent', 'cancelled', 'failed');
    END IF;
END$$;

-- Reminders / notifications
CREATE TABLE IF NOT EXISTS task_reminder (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id uuid NOT NULL REFERENCES task(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,

    remind_at timestamptz NOT NULL,
    channel reminder_channel NOT NULL DEFAULT 'in_app',
    status reminder_status NOT NULL DEFAULT 'scheduled',

    meta jsonb NOT NULL DEFAULT '{}'::jsonb,

    sent_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT task_reminder_sent_at_requires_sent CHECK (
        (sent_at IS NULL) OR (status = 'sent')
    )
);

CREATE INDEX IF NOT EXISTS idx_task_reminder_user_remind_at ON task_reminder(user_id, remind_at);
CREATE INDEX IF NOT EXISTS idx_task_reminder_task_id ON task_reminder(task_id);
CREATE INDEX IF NOT EXISTS idx_task_reminder_status ON task_reminder(status);
