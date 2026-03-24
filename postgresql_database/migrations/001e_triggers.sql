-- 001e - triggers (updated_at)
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DO $$
BEGIN
    -- app_user
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='app_user') THEN
        EXECUTE 'DROP TRIGGER IF EXISTS trg_app_user_updated_at ON app_user';
        EXECUTE 'CREATE TRIGGER trg_app_user_updated_at BEFORE UPDATE ON app_user FOR EACH ROW EXECUTE FUNCTION set_updated_at()';
    END IF;

    -- team
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='team') THEN
        EXECUTE 'DROP TRIGGER IF EXISTS trg_team_updated_at ON team';
        EXECUTE 'CREATE TRIGGER trg_team_updated_at BEFORE UPDATE ON team FOR EACH ROW EXECUTE FUNCTION set_updated_at()';
    END IF;

    -- task_list
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='task_list') THEN
        EXECUTE 'DROP TRIGGER IF EXISTS trg_task_list_updated_at ON task_list';
        EXECUTE 'CREATE TRIGGER trg_task_list_updated_at BEFORE UPDATE ON task_list FOR EACH ROW EXECUTE FUNCTION set_updated_at()';
    END IF;

    -- task
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='task') THEN
        EXECUTE 'DROP TRIGGER IF EXISTS trg_task_updated_at ON task';
        EXECUTE 'CREATE TRIGGER trg_task_updated_at BEFORE UPDATE ON task FOR EACH ROW EXECUTE FUNCTION set_updated_at()';
    END IF;

    -- task_note
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='task_note') THEN
        EXECUTE 'DROP TRIGGER IF EXISTS trg_task_note_updated_at ON task_note';
        EXECUTE 'CREATE TRIGGER trg_task_note_updated_at BEFORE UPDATE ON task_note FOR EACH ROW EXECUTE FUNCTION set_updated_at()';
    END IF;

    -- recurring_rule
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='recurring_rule') THEN
        EXECUTE 'DROP TRIGGER IF EXISTS trg_recurring_rule_updated_at ON recurring_rule';
        EXECUTE 'CREATE TRIGGER trg_recurring_rule_updated_at BEFORE UPDATE ON recurring_rule FOR EACH ROW EXECUTE FUNCTION set_updated_at()';
    END IF;

    -- task_reminder
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='task_reminder') THEN
        EXECUTE 'DROP TRIGGER IF EXISTS trg_task_reminder_updated_at ON task_reminder';
        EXECUTE 'CREATE TRIGGER trg_task_reminder_updated_at BEFORE UPDATE ON task_reminder FOR EACH ROW EXECUTE FUNCTION set_updated_at()';
    END IF;
END;
$$;
