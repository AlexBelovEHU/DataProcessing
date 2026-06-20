\set ON_ERROR_STOP on

SET search_path = compute_marketplace, public;

BEGIN;

CREATE TEMP TABLE stg_user_profiles (
    email text,
    password_hash text,
    role_code text,
    name text,
    organization text,
    balance numeric(14, 2),
    created_at timestamptz
) ON COMMIT DROP;

CREATE TEMP TABLE stg_nodes (
    node_code text,
    provider_email text,
    status_code text,
    created_at timestamptz,
    cpu_cores integer,
    ram_gb numeric(10, 2),
    gpu_model text,
    gpu_vram_gb numeric(10, 2),
    disk_gb numeric(10, 2),
    price_cpu_hour numeric(10, 2),
    price_gpu_hour numeric(10, 2),
    price_ram_gb_hour numeric(10, 2)
) ON COMMIT DROP;

CREATE TEMP TABLE stg_tasks (
    task_ref text,
    buyer_email text,
    status_code text,
    created_at timestamptz,
    total_cost numeric(14, 2),
    solver_type text,
    parameters_json text,
    docker_image text,
    estimated_cost numeric(14, 2)
) ON COMMIT DROP;

CREATE TEMP TABLE stg_jobs (
    job_ref text,
    task_ref text,
    node_code text,
    status_code text,
    retry_count integer,
    created_at timestamptz,
    started_at timestamptz,
    finished_at timestamptz,
    output_path text,
    checksum text,
    validation_status_code text,
    validation_reason text,
    cpu_cost numeric(14, 2),
    gpu_cost numeric(14, 2),
    total_cost numeric(14, 2)
) ON COMMIT DROP;

CREATE TEMP TABLE stg_operations (
    record_type text,
    event_ref text,
    job_ref text,
    user_email text,
    provider_email text,
    event_code text,
    amount numeric(14, 2),
    cpu_usage numeric(10, 2),
    gpu_usage numeric(10, 2),
    memory_usage numeric(10, 2),
    event_timestamp timestamptz,
    message text
) ON COMMIT DROP;

\copy stg_user_profiles FROM './data/user_profiles.csv' WITH (FORMAT csv, HEADER true)
\copy stg_nodes FROM './data/nodes.csv' WITH (FORMAT csv, HEADER true)
\copy stg_tasks FROM './data/tasks.csv' WITH (FORMAT csv, HEADER true)
\copy stg_jobs FROM './data/jobs.csv' WITH (FORMAT csv, HEADER true)
\copy stg_operations FROM './data/operations.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO users (email, password_hash, role_code, created_at)
SELECT DISTINCT
    trim(email),
    password_hash,
    role_code,
    created_at
FROM stg_user_profiles
ON CONFLICT (email) DO UPDATE
SET
    password_hash = EXCLUDED.password_hash,
    role_code = EXCLUDED.role_code,
    created_at = EXCLUDED.created_at
WHERE
    users.password_hash IS DISTINCT FROM EXCLUDED.password_hash
    OR users.role_code IS DISTINCT FROM EXCLUDED.role_code
    OR users.created_at IS DISTINCT FROM EXCLUDED.created_at;

INSERT INTO profiles (user_id, name, organization, balance)
SELECT
    u.user_id,
    s.name,
    s.organization,
    s.balance
FROM stg_user_profiles s
JOIN users u ON u.email = trim(s.email)
ON CONFLICT (user_id) DO UPDATE
SET
    name = EXCLUDED.name,
    organization = EXCLUDED.organization,
    balance = EXCLUDED.balance
WHERE
    profiles.name IS DISTINCT FROM EXCLUDED.name
    OR profiles.organization IS DISTINCT FROM EXCLUDED.organization
    OR profiles.balance IS DISTINCT FROM EXCLUDED.balance;

INSERT INTO nodes (node_code, provider_user_id, status_code, created_at)
SELECT DISTINCT
    trim(s.node_code),
    u.user_id,
    s.status_code,
    s.created_at
FROM stg_nodes s
JOIN users u ON u.email = trim(s.provider_email)
ON CONFLICT (node_code) DO UPDATE
SET
    provider_user_id = EXCLUDED.provider_user_id,
    status_code = EXCLUDED.status_code,
    created_at = EXCLUDED.created_at
WHERE
    nodes.provider_user_id IS DISTINCT FROM EXCLUDED.provider_user_id
    OR nodes.status_code IS DISTINCT FROM EXCLUDED.status_code
    OR nodes.created_at IS DISTINCT FROM EXCLUDED.created_at;

INSERT INTO node_specs (node_id, cpu_cores, ram_gb, gpu_model, gpu_vram_gb, disk_gb)
SELECT
    n.node_id,
    s.cpu_cores,
    s.ram_gb,
    NULLIF(s.gpu_model, ''),
    s.gpu_vram_gb,
    s.disk_gb
FROM stg_nodes s
JOIN nodes n ON n.node_code = trim(s.node_code)
ON CONFLICT (node_id) DO UPDATE
SET
    cpu_cores = EXCLUDED.cpu_cores,
    ram_gb = EXCLUDED.ram_gb,
    gpu_model = EXCLUDED.gpu_model,
    gpu_vram_gb = EXCLUDED.gpu_vram_gb,
    disk_gb = EXCLUDED.disk_gb
WHERE
    node_specs.cpu_cores IS DISTINCT FROM EXCLUDED.cpu_cores
    OR node_specs.ram_gb IS DISTINCT FROM EXCLUDED.ram_gb
    OR node_specs.gpu_model IS DISTINCT FROM EXCLUDED.gpu_model
    OR node_specs.gpu_vram_gb IS DISTINCT FROM EXCLUDED.gpu_vram_gb
    OR node_specs.disk_gb IS DISTINCT FROM EXCLUDED.disk_gb;

INSERT INTO node_pricing (node_id, price_cpu_hour, price_gpu_hour, price_ram_gb_hour)
SELECT
    n.node_id,
    s.price_cpu_hour,
    s.price_gpu_hour,
    s.price_ram_gb_hour
FROM stg_nodes s
JOIN nodes n ON n.node_code = trim(s.node_code)
ON CONFLICT (node_id) DO UPDATE
SET
    price_cpu_hour = EXCLUDED.price_cpu_hour,
    price_gpu_hour = EXCLUDED.price_gpu_hour,
    price_ram_gb_hour = EXCLUDED.price_ram_gb_hour
WHERE
    node_pricing.price_cpu_hour IS DISTINCT FROM EXCLUDED.price_cpu_hour
    OR node_pricing.price_gpu_hour IS DISTINCT FROM EXCLUDED.price_gpu_hour
    OR node_pricing.price_ram_gb_hour IS DISTINCT FROM EXCLUDED.price_ram_gb_hour;

INSERT INTO tasks (task_ref, user_id, status_code, total_cost, created_at)
SELECT DISTINCT
    trim(s.task_ref),
    u.user_id,
    s.status_code,
    s.total_cost,
    s.created_at
FROM stg_tasks s
JOIN users u ON u.email = trim(s.buyer_email)
ON CONFLICT (task_ref) DO UPDATE
SET
    user_id = EXCLUDED.user_id,
    status_code = EXCLUDED.status_code,
    total_cost = EXCLUDED.total_cost,
    created_at = EXCLUDED.created_at
WHERE
    tasks.user_id IS DISTINCT FROM EXCLUDED.user_id
    OR tasks.status_code IS DISTINCT FROM EXCLUDED.status_code
    OR tasks.total_cost IS DISTINCT FROM EXCLUDED.total_cost
    OR tasks.created_at IS DISTINCT FROM EXCLUDED.created_at;

INSERT INTO task_configs (task_id, solver_type, parameters_json, docker_image, estimated_cost)
SELECT
    t.task_id,
    s.solver_type,
    s.parameters_json::jsonb,
    s.docker_image,
    s.estimated_cost
FROM stg_tasks s
JOIN tasks t ON t.task_ref = trim(s.task_ref)
ON CONFLICT (task_id) DO UPDATE
SET
    solver_type = EXCLUDED.solver_type,
    parameters_json = EXCLUDED.parameters_json,
    docker_image = EXCLUDED.docker_image,
    estimated_cost = EXCLUDED.estimated_cost
WHERE
    task_configs.solver_type IS DISTINCT FROM EXCLUDED.solver_type
    OR task_configs.parameters_json IS DISTINCT FROM EXCLUDED.parameters_json
    OR task_configs.docker_image IS DISTINCT FROM EXCLUDED.docker_image
    OR task_configs.estimated_cost IS DISTINCT FROM EXCLUDED.estimated_cost;

INSERT INTO jobs (job_ref, task_id, node_id, status_code, retry_count, created_at, started_at, finished_at)
SELECT DISTINCT
    trim(s.job_ref),
    t.task_id,
    n.node_id,
    s.status_code,
    s.retry_count,
    s.created_at,
    s.started_at,
    s.finished_at
FROM stg_jobs s
JOIN tasks t ON t.task_ref = trim(s.task_ref)
LEFT JOIN nodes n ON n.node_code = NULLIF(trim(s.node_code), '')
ON CONFLICT (job_ref) DO UPDATE
SET
    task_id = EXCLUDED.task_id,
    node_id = EXCLUDED.node_id,
    status_code = EXCLUDED.status_code,
    retry_count = EXCLUDED.retry_count,
    created_at = EXCLUDED.created_at,
    started_at = EXCLUDED.started_at,
    finished_at = EXCLUDED.finished_at
WHERE
    jobs.task_id IS DISTINCT FROM EXCLUDED.task_id
    OR jobs.node_id IS DISTINCT FROM EXCLUDED.node_id
    OR jobs.status_code IS DISTINCT FROM EXCLUDED.status_code
    OR jobs.retry_count IS DISTINCT FROM EXCLUDED.retry_count
    OR jobs.created_at IS DISTINCT FROM EXCLUDED.created_at
    OR jobs.started_at IS DISTINCT FROM EXCLUDED.started_at
    OR jobs.finished_at IS DISTINCT FROM EXCLUDED.finished_at;

INSERT INTO job_results (job_id, output_path, checksum, created_at)
SELECT
    j.job_id,
    s.output_path,
    s.checksum,
    COALESCE(s.finished_at, s.created_at)
FROM stg_jobs s
JOIN jobs j ON j.job_ref = trim(s.job_ref)
WHERE NULLIF(s.output_path, '') IS NOT NULL
  AND NULLIF(s.checksum, '') IS NOT NULL
ON CONFLICT (job_id) DO UPDATE
SET
    output_path = EXCLUDED.output_path,
    checksum = EXCLUDED.checksum,
    created_at = EXCLUDED.created_at
WHERE
    job_results.output_path IS DISTINCT FROM EXCLUDED.output_path
    OR job_results.checksum IS DISTINCT FROM EXCLUDED.checksum
    OR job_results.created_at IS DISTINCT FROM EXCLUDED.created_at;

INSERT INTO validations (job_id, status_code, reason, created_at)
SELECT
    j.job_id,
    s.validation_status_code,
    NULLIF(s.validation_reason, ''),
    COALESCE(s.finished_at, s.created_at)
FROM stg_jobs s
JOIN jobs j ON j.job_ref = trim(s.job_ref)
WHERE NULLIF(s.validation_status_code, '') IS NOT NULL
ON CONFLICT (job_id) DO UPDATE
SET
    status_code = EXCLUDED.status_code,
    reason = EXCLUDED.reason,
    created_at = EXCLUDED.created_at
WHERE
    validations.status_code IS DISTINCT FROM EXCLUDED.status_code
    OR validations.reason IS DISTINCT FROM EXCLUDED.reason
    OR validations.created_at IS DISTINCT FROM EXCLUDED.created_at;

INSERT INTO job_costs (job_id, cpu_cost, gpu_cost, total_cost)
SELECT
    j.job_id,
    s.cpu_cost,
    s.gpu_cost,
    s.total_cost
FROM stg_jobs s
JOIN jobs j ON j.job_ref = trim(s.job_ref)
WHERE s.cpu_cost IS NOT NULL
  AND s.gpu_cost IS NOT NULL
  AND s.total_cost IS NOT NULL
ON CONFLICT (job_id) DO UPDATE
SET
    cpu_cost = EXCLUDED.cpu_cost,
    gpu_cost = EXCLUDED.gpu_cost,
    total_cost = EXCLUDED.total_cost
WHERE
    job_costs.cpu_cost IS DISTINCT FROM EXCLUDED.cpu_cost
    OR job_costs.gpu_cost IS DISTINCT FROM EXCLUDED.gpu_cost
    OR job_costs.total_cost IS DISTINCT FROM EXCLUDED.total_cost;

INSERT INTO job_metrics (job_id, metric_timestamp, cpu_usage, gpu_usage, memory_usage)
SELECT
    j.job_id,
    s.event_timestamp,
    s.cpu_usage,
    s.gpu_usage,
    s.memory_usage
FROM stg_operations s
JOIN jobs j ON j.job_ref = trim(s.job_ref)
WHERE s.record_type = 'job_metric'
ON CONFLICT (job_id, metric_timestamp) DO UPDATE
SET
    cpu_usage = EXCLUDED.cpu_usage,
    gpu_usage = EXCLUDED.gpu_usage,
    memory_usage = EXCLUDED.memory_usage
WHERE
    job_metrics.cpu_usage IS DISTINCT FROM EXCLUDED.cpu_usage
    OR job_metrics.gpu_usage IS DISTINCT FROM EXCLUDED.gpu_usage
    OR job_metrics.memory_usage IS DISTINCT FROM EXCLUDED.memory_usage;

INSERT INTO job_logs (job_id, log_sequence, log_text, created_at)
SELECT
    j.job_id,
    s.event_ref::integer,
    s.message,
    s.event_timestamp
FROM stg_operations s
JOIN jobs j ON j.job_ref = trim(s.job_ref)
WHERE s.record_type = 'job_log'
ON CONFLICT (job_id, log_sequence) DO UPDATE
SET
    log_text = EXCLUDED.log_text,
    created_at = EXCLUDED.created_at
WHERE
    job_logs.log_text IS DISTINCT FROM EXCLUDED.log_text
    OR job_logs.created_at IS DISTINCT FROM EXCLUDED.created_at;

INSERT INTO transactions (transaction_ref, user_id, transaction_type_code, amount, created_at)
SELECT
    s.event_ref,
    u.user_id,
    s.event_code,
    s.amount,
    s.event_timestamp
FROM stg_operations s
JOIN users u ON u.email = trim(s.user_email)
WHERE s.record_type = 'transaction'
ON CONFLICT (transaction_ref) DO UPDATE
SET
    user_id = EXCLUDED.user_id,
    transaction_type_code = EXCLUDED.transaction_type_code,
    amount = EXCLUDED.amount,
    created_at = EXCLUDED.created_at
WHERE
    transactions.user_id IS DISTINCT FROM EXCLUDED.user_id
    OR transactions.transaction_type_code IS DISTINCT FROM EXCLUDED.transaction_type_code
    OR transactions.amount IS DISTINCT FROM EXCLUDED.amount
    OR transactions.created_at IS DISTINCT FROM EXCLUDED.created_at;

INSERT INTO payouts (payout_ref, provider_user_id, amount, payout_status_code, created_at)
SELECT
    s.event_ref,
    u.user_id,
    s.amount,
    s.event_code,
    s.event_timestamp
FROM stg_operations s
JOIN users u ON u.email = trim(s.provider_email)
WHERE s.record_type = 'payout'
ON CONFLICT (payout_ref) DO UPDATE
SET
    provider_user_id = EXCLUDED.provider_user_id,
    amount = EXCLUDED.amount,
    payout_status_code = EXCLUDED.payout_status_code,
    created_at = EXCLUDED.created_at
WHERE
    payouts.provider_user_id IS DISTINCT FROM EXCLUDED.provider_user_id
    OR payouts.amount IS DISTINCT FROM EXCLUDED.amount
    OR payouts.payout_status_code IS DISTINCT FROM EXCLUDED.payout_status_code
    OR payouts.created_at IS DISTINCT FROM EXCLUDED.created_at;

COMMIT;