CREATE SCHEMA IF NOT EXISTS compute_marketplace;

SET search_path = compute_marketplace, public;

CREATE TABLE IF NOT EXISTS role_types (
    role_code text PRIMARY KEY,
    role_name text NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS node_statuses (
    status_code text PRIMARY KEY,
    description text NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS task_statuses (
    status_code text PRIMARY KEY,
    description text NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS job_statuses (
    status_code text PRIMARY KEY,
    description text NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS validation_statuses (
    status_code text PRIMARY KEY,
    description text NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS transaction_types (
    transaction_type_code text PRIMARY KEY,
    description text NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS payout_statuses (
    payout_status_code text PRIMARY KEY,
    description text NOT NULL UNIQUE
);

INSERT INTO role_types (role_code, role_name)
VALUES
    ('buyer', 'Buyer'),
    ('provider', 'Provider'),
    ('admin', 'Administrator')
ON CONFLICT (role_code) DO NOTHING;

INSERT INTO node_statuses (status_code, description)
VALUES
    ('online', 'Ready to accept jobs'),
    ('offline', 'Unavailable'),
    ('busy', 'Currently executing work')
ON CONFLICT (status_code) DO NOTHING;

INSERT INTO task_statuses (status_code, description)
VALUES
    ('created', 'Created but not started'),
    ('running', 'At least one job is running'),
    ('completed', 'All jobs completed successfully'),
    ('failed', 'Task finished with failure')
ON CONFLICT (status_code) DO NOTHING;

INSERT INTO job_statuses (status_code, description)
VALUES
    ('queued', 'Queued for scheduling'),
    ('running', 'Running on a node'),
    ('failed', 'Execution failed'),
    ('completed', 'Execution finished successfully')
ON CONFLICT (status_code) DO NOTHING;

INSERT INTO validation_statuses (status_code, description)
VALUES
    ('valid', 'Validation passed'),
    ('invalid', 'Validation failed')
ON CONFLICT (status_code) DO NOTHING;

INSERT INTO transaction_types (transaction_type_code, description)
VALUES
    ('debit', 'Money charged from a user account'),
    ('credit', 'Money added to a user account')
ON CONFLICT (transaction_type_code) DO NOTHING;

INSERT INTO payout_statuses (payout_status_code, description)
VALUES
    ('pending', 'Awaiting payout'),
    ('paid', 'Provider has been paid')
ON CONFLICT (payout_status_code) DO NOTHING;

CREATE TABLE IF NOT EXISTS users (
    user_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email text NOT NULL UNIQUE,
    password_hash text NOT NULL,
    role_code text NOT NULL REFERENCES role_types(role_code),
    created_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS profiles (
    user_id bigint PRIMARY KEY REFERENCES users(user_id),
    name text NOT NULL,
    organization text,
    balance numeric(14, 2) NOT NULL DEFAULT 0,
    CHECK (balance >= 0)
);

CREATE TABLE IF NOT EXISTS nodes (
    node_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    node_code text NOT NULL UNIQUE,
    provider_user_id bigint NOT NULL REFERENCES users(user_id),
    status_code text NOT NULL REFERENCES node_statuses(status_code),
    created_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS node_specs (
    node_id bigint PRIMARY KEY REFERENCES nodes(node_id),
    cpu_cores integer NOT NULL CHECK (cpu_cores > 0),
    ram_gb numeric(10, 2) NOT NULL CHECK (ram_gb > 0),
    gpu_model text,
    gpu_vram_gb numeric(10, 2),
    disk_gb numeric(10, 2) NOT NULL CHECK (disk_gb > 0)
);

CREATE TABLE IF NOT EXISTS node_pricing (
    node_id bigint PRIMARY KEY REFERENCES nodes(node_id),
    price_cpu_hour numeric(10, 2) NOT NULL CHECK (price_cpu_hour >= 0),
    price_gpu_hour numeric(10, 2) NOT NULL CHECK (price_gpu_hour >= 0),
    price_ram_gb_hour numeric(10, 2) NOT NULL CHECK (price_ram_gb_hour >= 0)
);

CREATE TABLE IF NOT EXISTS tasks (
    task_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    task_ref text NOT NULL UNIQUE,
    user_id bigint NOT NULL REFERENCES users(user_id),
    status_code text NOT NULL REFERENCES task_statuses(status_code),
    total_cost numeric(14, 2) NOT NULL DEFAULT 0 CHECK (total_cost >= 0),
    created_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS task_configs (
    task_id bigint PRIMARY KEY REFERENCES tasks(task_id),
    solver_type text NOT NULL,
    parameters_json jsonb NOT NULL,
    docker_image text NOT NULL,
    estimated_cost numeric(14, 2) NOT NULL CHECK (estimated_cost >= 0)
);

CREATE TABLE IF NOT EXISTS jobs (
    job_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_ref text NOT NULL UNIQUE,
    task_id bigint NOT NULL REFERENCES tasks(task_id),
    node_id bigint REFERENCES nodes(node_id),
    status_code text NOT NULL REFERENCES job_statuses(status_code),
    retry_count integer NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    created_at timestamptz NOT NULL,
    started_at timestamptz,
    finished_at timestamptz,
    CHECK (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at)
);

CREATE TABLE IF NOT EXISTS job_results (
    job_id bigint PRIMARY KEY REFERENCES jobs(job_id),
    output_path text NOT NULL,
    checksum text NOT NULL,
    created_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS validations (
    job_id bigint PRIMARY KEY REFERENCES jobs(job_id),
    status_code text NOT NULL REFERENCES validation_statuses(status_code),
    reason text,
    created_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS job_metrics (
    job_id bigint NOT NULL REFERENCES jobs(job_id),
    metric_timestamp timestamptz NOT NULL,
    cpu_usage numeric(6, 2) NOT NULL CHECK (cpu_usage >= 0),
    gpu_usage numeric(6, 2) NOT NULL CHECK (gpu_usage >= 0),
    memory_usage numeric(10, 2) NOT NULL CHECK (memory_usage >= 0),
    PRIMARY KEY (job_id, metric_timestamp)
);

CREATE TABLE IF NOT EXISTS job_logs (
    job_id bigint NOT NULL REFERENCES jobs(job_id),
    log_sequence integer NOT NULL CHECK (log_sequence > 0),
    log_text text NOT NULL,
    created_at timestamptz NOT NULL,
    PRIMARY KEY (job_id, log_sequence)
);

CREATE TABLE IF NOT EXISTS transactions (
    transaction_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_ref text NOT NULL UNIQUE,
    user_id bigint NOT NULL REFERENCES users(user_id),
    transaction_type_code text NOT NULL REFERENCES transaction_types(transaction_type_code),
    amount numeric(14, 2) NOT NULL CHECK (amount > 0),
    created_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS job_costs (
    job_id bigint PRIMARY KEY REFERENCES jobs(job_id),
    cpu_cost numeric(14, 2) NOT NULL CHECK (cpu_cost >= 0),
    gpu_cost numeric(14, 2) NOT NULL CHECK (gpu_cost >= 0),
    total_cost numeric(14, 2) NOT NULL CHECK (total_cost >= 0)
);

CREATE TABLE IF NOT EXISTS payouts (
    payout_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payout_ref text NOT NULL UNIQUE,
    provider_user_id bigint NOT NULL REFERENCES users(user_id),
    amount numeric(14, 2) NOT NULL CHECK (amount > 0),
    payout_status_code text NOT NULL REFERENCES payout_statuses(payout_status_code),
    created_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_jobs_task_status
    ON jobs (task_id, status_code);

CREATE INDEX IF NOT EXISTS idx_jobs_node
    ON jobs (node_id);

CREATE INDEX IF NOT EXISTS idx_job_metrics_job_ts
    ON job_metrics (job_id, metric_timestamp);

CREATE INDEX IF NOT EXISTS idx_transactions_user_created
    ON transactions (user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_nodes_status
    ON nodes (status_code);