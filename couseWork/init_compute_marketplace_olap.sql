\set ON_ERROR_STOP on

\if :{?olap_db}
\else
\set olap_db compute_marketplace_olap
\endif

SELECT format('CREATE DATABASE %I', :'olap_db')
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_database
    WHERE datname = :'olap_db'
) \gexec

\connect :olap_db

CREATE SCHEMA IF NOT EXISTS marketplace_dw;

SET search_path = marketplace_dw, public;

CREATE TABLE IF NOT EXISTS dim_date (
    date_key integer PRIMARY KEY,
    full_date date NOT NULL UNIQUE,
    day_of_week integer NOT NULL,
    day_name text NOT NULL,
    day_of_month integer NOT NULL,
    month_number integer NOT NULL,
    month_name text NOT NULL,
    quarter_number integer NOT NULL,
    year_number integer NOT NULL,
    week_of_year integer NOT NULL,
    is_weekend boolean NOT NULL
);

CREATE TABLE IF NOT EXISTS dim_organization (
    organization_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organization_name text NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS dim_user_account_scd2 (
    user_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_nk text NOT NULL,
    user_name text NOT NULL,
    role_code text NOT NULL,
    organization_sk bigint REFERENCES dim_organization(organization_sk),
    effective_from timestamptz NOT NULL,
    effective_to timestamptz NOT NULL,
    is_current boolean NOT NULL DEFAULT true,
    CONSTRAINT uq_dim_user_account_scd2 UNIQUE (user_nk, effective_from),
    CONSTRAINT chk_dim_user_account_scd2_dates CHECK (effective_to > effective_from)
);

CREATE INDEX IF NOT EXISTS idx_dim_user_account_scd2_current
    ON dim_user_account_scd2 (user_nk, is_current, effective_from, effective_to);

CREATE TABLE IF NOT EXISTS dim_solver_family (
    solver_family_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    solver_family_code text NOT NULL UNIQUE,
    solver_family_name text NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS dim_solver (
    solver_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    solver_type text NOT NULL UNIQUE,
    solver_family_sk bigint NOT NULL REFERENCES dim_solver_family(solver_family_sk)
);

CREATE TABLE IF NOT EXISTS dim_workload_profile (
    workload_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workload_nk text NOT NULL UNIQUE,
    solver_sk bigint NOT NULL REFERENCES dim_solver(solver_sk),
    docker_image text NOT NULL,
    parameter_signature text NOT NULL,
    estimated_cost_band text NOT NULL
);

CREATE TABLE IF NOT EXISTS dim_parameter_tag (
    parameter_tag_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tag_key text NOT NULL,
    tag_value text NOT NULL,
    tag_label text NOT NULL,
    CONSTRAINT uq_dim_parameter_tag UNIQUE (tag_key, tag_value)
);

CREATE TABLE IF NOT EXISTS bridge_workload_parameter_tag (
    workload_sk bigint NOT NULL REFERENCES dim_workload_profile(workload_sk),
    parameter_tag_sk bigint NOT NULL REFERENCES dim_parameter_tag(parameter_tag_sk),
    allocation_weight numeric(8, 4) NOT NULL DEFAULT 1,
    PRIMARY KEY (workload_sk, parameter_tag_sk)
);

CREATE TABLE IF NOT EXISTS dim_gpu_family (
    gpu_family_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gpu_family_name text NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS dim_node (
    node_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    node_nk text NOT NULL UNIQUE,
    gpu_family_sk bigint REFERENCES dim_gpu_family(gpu_family_sk),
    gpu_model text,
    cpu_cores integer NOT NULL,
    ram_gb numeric(10, 2) NOT NULL,
    gpu_vram_gb numeric(10, 2),
    disk_gb numeric(10, 2) NOT NULL,
    performance_tier text NOT NULL,
    price_band text NOT NULL
);

CREATE TABLE IF NOT EXISTS dim_task_status (
    task_status_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    status_code text NOT NULL UNIQUE,
    status_group text NOT NULL
);

INSERT INTO dim_task_status (status_code, status_group)
VALUES
    ('created', 'Open'),
    ('running', 'In Progress'),
    ('completed', 'Closed'),
    ('failed', 'Closed')
ON CONFLICT (status_code) DO NOTHING;

CREATE TABLE IF NOT EXISTS dim_job_outcome (
    job_outcome_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_status_code text NOT NULL,
    validation_status_code text NOT NULL,
    outcome_label text NOT NULL,
    CONSTRAINT uq_dim_job_outcome UNIQUE (job_status_code, validation_status_code)
);

INSERT INTO dim_job_outcome (job_status_code, validation_status_code, outcome_label)
VALUES
    ('queued', 'not_checked', 'Queued'),
    ('running', 'not_checked', 'Running'),
    ('completed', 'valid', 'Completed and valid'),
    ('completed', 'invalid', 'Completed but invalid'),
    ('completed', 'not_checked', 'Completed without validation'),
    ('failed', 'not_checked', 'Failed')
ON CONFLICT (job_status_code, validation_status_code) DO NOTHING;

CREATE TABLE IF NOT EXISTS dim_finance_event (
    finance_event_sk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    finance_event_code text NOT NULL UNIQUE,
    finance_event_group text NOT NULL,
    flow_direction text NOT NULL
);

INSERT INTO dim_finance_event (finance_event_code, finance_event_group, flow_direction)
VALUES
    ('debit', 'Buyer Transactions', 'outflow'),
    ('credit', 'Buyer Transactions', 'inflow'),
    ('payout_pending', 'Provider Payouts', 'outflow'),
    ('payout_paid', 'Provider Payouts', 'outflow')
ON CONFLICT (finance_event_code) DO NOTHING;

CREATE TABLE IF NOT EXISTS fact_task_daily (
    date_key integer NOT NULL REFERENCES dim_date(date_key),
    buyer_user_sk bigint NOT NULL REFERENCES dim_user_account_scd2(user_sk),
    workload_sk bigint NOT NULL REFERENCES dim_workload_profile(workload_sk),
    task_status_sk bigint NOT NULL REFERENCES dim_task_status(task_status_sk),
    tasks_created_count integer NOT NULL,
    jobs_requested_count integer NOT NULL,
    total_estimated_cost numeric(14, 2) NOT NULL,
    total_actual_cost numeric(14, 2) NOT NULL,
    completed_tasks_count integer NOT NULL,
    failed_tasks_count integer NOT NULL,
    PRIMARY KEY (date_key, buyer_user_sk, workload_sk, task_status_sk)
);

CREATE TABLE IF NOT EXISTS fact_job_execution_daily (
    date_key integer NOT NULL REFERENCES dim_date(date_key),
    buyer_user_sk bigint NOT NULL REFERENCES dim_user_account_scd2(user_sk),
    provider_user_sk bigint REFERENCES dim_user_account_scd2(user_sk),
    node_sk bigint REFERENCES dim_node(node_sk),
    workload_sk bigint NOT NULL REFERENCES dim_workload_profile(workload_sk),
    job_outcome_sk bigint NOT NULL REFERENCES dim_job_outcome(job_outcome_sk),
    jobs_count integer NOT NULL,
    total_runtime_minutes numeric(16, 2) NOT NULL,
    total_cpu_cost numeric(14, 2) NOT NULL,
    total_gpu_cost numeric(14, 2) NOT NULL,
    total_job_cost numeric(14, 2) NOT NULL,
    avg_cpu_usage numeric(10, 2),
    avg_gpu_usage numeric(10, 2),
    avg_memory_usage numeric(10, 2),
    PRIMARY KEY (date_key, buyer_user_sk, provider_user_sk, node_sk, workload_sk, job_outcome_sk)
);

CREATE TABLE IF NOT EXISTS fact_finance_daily (
    date_key integer NOT NULL REFERENCES dim_date(date_key),
    user_sk bigint NOT NULL REFERENCES dim_user_account_scd2(user_sk),
    finance_event_sk bigint NOT NULL REFERENCES dim_finance_event(finance_event_sk),
    event_count integer NOT NULL,
    total_amount numeric(14, 2) NOT NULL,
    PRIMARY KEY (date_key, user_sk, finance_event_sk)
);

CREATE INDEX IF NOT EXISTS idx_fact_task_daily_date
    ON fact_task_daily (date_key);

CREATE INDEX IF NOT EXISTS idx_fact_job_execution_daily_date
    ON fact_job_execution_daily (date_key);

CREATE INDEX IF NOT EXISTS idx_fact_finance_daily_date
    ON fact_finance_daily (date_key);

CREATE OR REPLACE VIEW vw_powerbi_task_summary AS
SELECT
    dd.full_date,
    du.user_name AS buyer_name,
    org.organization_name,
    sf.solver_family_name,
    ds.solver_type,
    ts.status_code AS task_status,
    ftd.tasks_created_count,
    ftd.jobs_requested_count,
    ftd.total_estimated_cost,
    ftd.total_actual_cost,
    ftd.completed_tasks_count,
    ftd.failed_tasks_count
FROM fact_task_daily ftd
JOIN dim_date dd ON dd.date_key = ftd.date_key
JOIN dim_user_account_scd2 du ON du.user_sk = ftd.buyer_user_sk
LEFT JOIN dim_organization org ON org.organization_sk = du.organization_sk
JOIN dim_workload_profile dwp ON dwp.workload_sk = ftd.workload_sk
JOIN dim_solver ds ON ds.solver_sk = dwp.solver_sk
JOIN dim_solver_family sf ON sf.solver_family_sk = ds.solver_family_sk
JOIN dim_task_status ts ON ts.task_status_sk = ftd.task_status_sk;

CREATE OR REPLACE VIEW vw_powerbi_job_execution AS
SELECT
    dd.full_date,
    buyer.user_name AS buyer_name,
    provider.user_name AS provider_name,
    buyer_org.organization_name AS buyer_organization,
    provider_org.organization_name AS provider_organization,
    dn.node_nk AS node_code,
    ds.solver_type,
    sf.solver_family_name,
    djo.outcome_label,
    fjd.jobs_count,
    fjd.total_runtime_minutes,
    fjd.total_cpu_cost,
    fjd.total_gpu_cost,
    fjd.total_job_cost,
    fjd.avg_cpu_usage,
    fjd.avg_gpu_usage,
    fjd.avg_memory_usage
FROM fact_job_execution_daily fjd
JOIN dim_date dd ON dd.date_key = fjd.date_key
JOIN dim_user_account_scd2 buyer ON buyer.user_sk = fjd.buyer_user_sk
LEFT JOIN dim_user_account_scd2 provider ON provider.user_sk = fjd.provider_user_sk
LEFT JOIN dim_organization buyer_org ON buyer_org.organization_sk = buyer.organization_sk
LEFT JOIN dim_organization provider_org ON provider_org.organization_sk = provider.organization_sk
LEFT JOIN dim_node dn ON dn.node_sk = fjd.node_sk
JOIN dim_workload_profile dwp ON dwp.workload_sk = fjd.workload_sk
JOIN dim_solver ds ON ds.solver_sk = dwp.solver_sk
JOIN dim_solver_family sf ON sf.solver_family_sk = ds.solver_family_sk
JOIN dim_job_outcome djo ON djo.job_outcome_sk = fjd.job_outcome_sk;

CREATE OR REPLACE VIEW vw_powerbi_finance AS
SELECT
    dd.full_date,
    du.user_name,
    org.organization_name,
    dfe.finance_event_group,
    dfe.finance_event_code,
    dfe.flow_direction,
    ffd.event_count,
    ffd.total_amount
FROM fact_finance_daily ffd
JOIN dim_date dd ON dd.date_key = ffd.date_key
JOIN dim_user_account_scd2 du ON du.user_sk = ffd.user_sk
LEFT JOIN dim_organization org ON org.organization_sk = du.organization_sk
JOIN dim_finance_event dfe ON dfe.finance_event_sk = ffd.finance_event_sk;