-- Task Planner Domain - Initial Schema (bootstrap)
-- This file is applied by postgresql_database/startup.sh.
-- It is intentionally small and includes the rest of the migration parts in order.

\set ON_ERROR_STOP on

BEGIN;

\i migrations/001a_extensions_and_users.sql
\i migrations/001b_teams_and_lists.sql
\i migrations/001c_tasks_tags_notes_attachments.sql
\i migrations/001d_recurring_and_reminders.sql
\i migrations/001e_triggers.sql

COMMIT;
