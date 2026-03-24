#!/bin/bash

# Minimal PostgreSQL startup script with full paths
# Initializes the database server, creates the application database/user,
# and bootstraps the task-planner schema + seed data.
DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"
DB_PORT="5000"

echo "Starting PostgreSQL setup..."

# Find PostgreSQL version and set paths
PG_VERSION=$(ls /usr/lib/postgresql/ | head -1)
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "Found PostgreSQL version: ${PG_VERSION}"

# Check if PostgreSQL is already running on the specified port
if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
    echo "PostgreSQL is already running on port ${DB_PORT}!"
    echo "Database: ${DB_NAME}"
    echo "User: ${DB_USER}"
    echo "Port: ${DB_PORT}"
    echo ""
    echo "To connect to the database, use:"
    echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"

    # Check if connection info file exists
    if [ -f "db_connection.txt" ]; then
        echo "Or use: $(cat db_connection.txt)"
    fi

    echo ""
    echo "Script stopped - server already running."
    exit 0
fi

# Also check if there's a PostgreSQL process running (in case pg_isready fails)
if pgrep -f "postgres.*-p ${DB_PORT}" > /dev/null 2>&1; then
    echo "Found existing PostgreSQL process on port ${DB_PORT}"
    echo "Attempting to verify connection..."

    # Try to connect and verify the database exists
    if sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c '\q' 2>/dev/null; then
        echo "Database ${DB_NAME} is accessible."
        echo "Script stopped - server already running."
        exit 0
    fi
fi

# Initialize PostgreSQL data directory if it doesn't exist
if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
    echo "Initializing PostgreSQL..."
    sudo -u postgres ${PG_BIN}/initdb -D /var/lib/postgresql/data
fi

# Start PostgreSQL server in background
echo "Starting PostgreSQL server..."
sudo -u postgres ${PG_BIN}/postgres -D /var/lib/postgresql/data -p ${DB_PORT} &

# Wait for PostgreSQL to start
echo "Waiting for PostgreSQL to start..."
sleep 5

# Check if PostgreSQL is running
for i in {1..15}; do
    if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
        echo "PostgreSQL is ready!"
        break
    fi
    echo "Waiting... ($i/15)"
    sleep 2
done

# Create database and user
echo "Setting up database and user..."
sudo -u postgres ${PG_BIN}/createdb -p ${DB_PORT} ${DB_NAME} 2>/dev/null || echo "Database might already exist"

# Create/ensure user and grant DB/schema privileges
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d postgres << EOF
-- Create user if doesn't exist
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$\$;

-- Grant database-level permissions
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};

-- Connect to the specific database for schema-level permissions
\c ${DB_NAME}

-- Allow working in public schema
GRANT USAGE ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};

-- Default privileges for objects created by postgres in public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};

-- Ensure the user can work with any existing objects
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};
EOF

# Save connection command to a file (repo convention: generated at runtime)
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > db_connection.txt
echo "Connection string saved to db_connection.txt"

# Save environment variables to a file for the built-in db_visualizer tool
cat > db_visualizer/postgres.env << EOF
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"
EOF

###############################################################################
# Schema initialization / seed
###############################################################################
echo "Bootstrapping task-planner schema (idempotent)..."

# Create extensions required for UUIDs and case-insensitive email
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS citext;"

# Users table (authentication is handled by backend, but we store user accounts here)
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS app_user (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext NOT NULL UNIQUE,
  display_name text,
  password_hash text, -- Optional; depending on backend auth strategy
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);"

# Teams (optional core)
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS team (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  owner_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_user_id, name)
);"

sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS team_member (
  team_id uuid NOT NULL REFERENCES team(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (team_id, user_id)
);"

# Lists / projects (support personal lists or team lists)
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS task_list (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  team_id uuid REFERENCES team(id) ON DELETE SET NULL,
  name text NOT NULL,
  description text,
  color text,
  is_archived boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_user_id, name)
);"

# Tasks
# status: todo/in_progress/done
# priority: low/medium/high/urgent
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS task (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  list_id uuid REFERENCES task_list(id) ON DELETE SET NULL,

  title text NOT NULL,
  description text,
  status text NOT NULL DEFAULT 'todo' CHECK (status IN ('todo','in_progress','done')),
  priority text NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high','urgent')),

  due_date date,
  due_at timestamptz,
  completed_at timestamptz,

  -- For board view ordering within a status column
  sort_order integer NOT NULL DEFAULT 0,

  -- Recurrence settings
  is_recurring boolean NOT NULL DEFAULT false,
  recurrence_rule text,  -- e.g., RFC5545 RRULE string; backend interprets
  recurrence_interval_days integer, -- simple recurrence helper
  recurrence_end_date date,
  next_occurrence_at timestamptz,

  -- Soft delete/archival
  is_archived boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);"

# Tags
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS tag (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  name text NOT NULL,
  color text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_user_id, name)
);"

sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS task_tag (
  task_id uuid NOT NULL REFERENCES task(id) ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (task_id, tag_id)
);"

# Notes (supports comments / rich notes per task)
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS task_note (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES task(id) ON DELETE CASCADE,
  author_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);"

# Attachments metadata (actual file storage typically external; backend manages)
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS task_attachment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES task(id) ON DELETE CASCADE,
  uploader_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
  file_name text NOT NULL,
  content_type text,
  size_bytes bigint,
  storage_key text, -- key/path in object storage or filesystem
  created_at timestamptz NOT NULL DEFAULT now()
);"

# Reminders / notifications (in-app/email handled by backend scheduler)
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS reminder (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES task(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  remind_at timestamptz NOT NULL,
  channel text NOT NULL DEFAULT 'in_app' CHECK (channel IN ('in_app','email')),
  status text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','sent','cancelled','failed')),
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);"

# Calendar events for tasks (optional; supports calendar view materialization)
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS calendar_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  task_id uuid REFERENCES task(id) ON DELETE CASCADE,
  title text NOT NULL,
  start_at timestamptz NOT NULL,
  end_at timestamptz,
  all_day boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);"

# Updated-at trigger function
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS \$\$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
\$\$ LANGUAGE plpgsql;"

# Triggers for updated_at
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_app_user_updated_at') THEN
    CREATE TRIGGER trg_app_user_updated_at BEFORE UPDATE ON app_user FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_team_updated_at') THEN
    CREATE TRIGGER trg_team_updated_at BEFORE UPDATE ON team FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_task_list_updated_at') THEN
    CREATE TRIGGER trg_task_list_updated_at BEFORE UPDATE ON task_list FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_task_updated_at') THEN
    CREATE TRIGGER trg_task_updated_at BEFORE UPDATE ON task FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_tag_updated_at') THEN
    CREATE TRIGGER trg_tag_updated_at BEFORE UPDATE ON tag FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_task_note_updated_at') THEN
    CREATE TRIGGER trg_task_note_updated_at BEFORE UPDATE ON task_note FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_reminder_updated_at') THEN
    CREATE TRIGGER trg_reminder_updated_at BEFORE UPDATE ON reminder FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_calendar_event_updated_at') THEN
    CREATE TRIGGER trg_calendar_event_updated_at BEFORE UPDATE ON calendar_event FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
END
\$\$;"

###############################################################################
# Indexes to support filtering/sorting/search
###############################################################################
# Common task filtering (user, list, status, priority, due)
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_task_owner_created_at ON task(owner_user_id, created_at DESC);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_task_owner_status_sort ON task(owner_user_id, status, sort_order ASC, updated_at DESC);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_task_owner_priority ON task(owner_user_id, priority);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_task_owner_due_date ON task(owner_user_id, due_date NULLS LAST);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_task_owner_due_at ON task(owner_user_id, due_at NULLS LAST);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_task_list_id ON task(list_id);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_task_deleted_at ON task(deleted_at) WHERE deleted_at IS NOT NULL;"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_task_archived ON task(is_archived) WHERE is_archived = true;"

# Recurring tasks
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_task_recurring_next ON task(owner_user_id, next_occurrence_at) WHERE is_recurring = true;"

# Tags
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_tag_owner_name ON tag(owner_user_id, name);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_task_tag_tag_id ON task_tag(tag_id);"

# Reminders
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_reminder_user_status_time ON reminder(user_id, status, remind_at);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_reminder_task_id ON reminder(task_id);"

# Calendar events
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_calendar_owner_start ON calendar_event(owner_user_id, start_at);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "CREATE INDEX IF NOT EXISTS idx_calendar_task_id ON calendar_event(task_id);"

# Basic full-text search on task title/description (for search box)
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
CREATE INDEX IF NOT EXISTS idx_task_fts
ON task
USING GIN (to_tsvector('english', coalesce(title,'') || ' ' || coalesce(description,'')))
;"

###############################################################################
# Seed (minimal, safe) - creates a demo user/list if DB is empty
###############################################################################
echo "Seeding minimal demo data (only if empty)..."

sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
INSERT INTO app_user (email, display_name)
SELECT 'demo@example.com', 'Demo User'
WHERE NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'demo@example.com');"

sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
INSERT INTO task_list (owner_user_id, name, description, color)
SELECT u.id, 'Inbox', 'Default list', '#3b82f6'
FROM app_user u
WHERE u.email = 'demo@example.com'
  AND NOT EXISTS (
    SELECT 1 FROM task_list l
    WHERE l.owner_user_id = u.id AND l.name = 'Inbox'
  );"

sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
INSERT INTO tag (owner_user_id, name, color)
SELECT u.id, 'Important', '#ef4444'
FROM app_user u
WHERE u.email = 'demo@example.com'
  AND NOT EXISTS (
    SELECT 1 FROM tag t
    WHERE t.owner_user_id = u.id AND t.name = 'Important'
  );"

sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
INSERT INTO task (owner_user_id, list_id, title, description, status, priority, due_date, sort_order)
SELECT u.id, l.id,
  'Welcome to your Task Planner',
  'Try editing this task, adding tags, and switching between list/board/calendar views.',
  'todo', 'medium',
  (current_date + 3),
  100
FROM app_user u
JOIN task_list l ON l.owner_user_id = u.id AND l.name = 'Inbox'
WHERE u.email = 'demo@example.com'
  AND NOT EXISTS (
    SELECT 1 FROM task t
    WHERE t.owner_user_id = u.id AND t.title = 'Welcome to your Task Planner'
  );"

sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
INSERT INTO task (owner_user_id, list_id, title, description, status, priority, due_at, sort_order)
SELECT u.id, l.id,
  'Schedule a reminder',
  'This task has a reminder scheduled 1 hour from now (in-app).',
  'in_progress', 'high',
  (now() + interval '1 day'),
  200
FROM app_user u
JOIN task_list l ON l.owner_user_id = u.id AND l.name = 'Inbox'
WHERE u.email = 'demo@example.com'
  AND NOT EXISTS (
    SELECT 1 FROM task t
    WHERE t.owner_user_id = u.id AND t.title = 'Schedule a reminder'
  );"

sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
INSERT INTO reminder (task_id, user_id, remind_at, channel, status)
SELECT t.id, u.id, (now() + interval '1 hour'), 'in_app', 'scheduled'
FROM app_user u
JOIN task t ON t.owner_user_id = u.id AND t.title = 'Schedule a reminder'
WHERE u.email = 'demo@example.com'
  AND NOT EXISTS (
    SELECT 1 FROM reminder r WHERE r.task_id = t.id AND r.user_id = u.id
  );"

sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -v ON_ERROR_STOP=1 -c "
INSERT INTO task_tag (task_id, tag_id)
SELECT t.id, tg.id
FROM app_user u
JOIN task t ON t.owner_user_id = u.id AND t.title = 'Welcome to your Task Planner'
JOIN tag tg ON tg.owner_user_id = u.id AND tg.name = 'Important'
WHERE u.email = 'demo@example.com'
  AND NOT EXISTS (
    SELECT 1 FROM task_tag tt WHERE tt.task_id = t.id AND tt.tag_id = tg.id
  );"

echo "PostgreSQL setup complete!"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Port: ${DB_PORT}"
echo ""
echo "Environment variables saved to db_visualizer/postgres.env"
echo "To use with Node.js viewer, run: source db_visualizer/postgres.env"
echo ""
echo "To connect to the database, use one of the following commands:"
echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
echo "$(cat db_connection.txt)"
