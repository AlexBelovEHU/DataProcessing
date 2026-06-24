\set ON_ERROR_STOP on

\if :{?olap_db}
\else
\set olap_db compute_marketplace_olap
\endif

\if :{?oltp_conn}
\else
\set oltp_conn 'host=localhost port=5432 dbname=compute_marketplace_oltp user=postgres'
\endif

\connect :olap_db

SET search_path = marketplace_dw, public;

CREATE EXTENSION IF NOT EXISTS dblink;

BEGIN;

CREATE TEMP TABLE etl_control (
    batch_ts timestamptz NOT NULL
) ON COMMIT DROP;

INSERT INTO etl_control (batch_ts)
VALUES (CURRENT_TIMESTAMP);

CREATE TEMP TABLE src_users ON COMMIT DROP AS
SELECT *
FROM dblink(:'oltp_conn', $$
    SELECT
        u.email,
        p.name,
        COALESCE(NULLIF(p.organization, ''), 'Independent') AS organization_name,
        u.role_code,
        u.created_at
    FROM compute_marketplace.users u
    JOIN compute_marketplace.profiles p
      ON p.user_id = u.user_id
$$) AS t (
    email text,
    name text,
    organization_name text,
    role_code text,
    created_at timestamptz
);

CREATE TEMP TABLE src_nodes ON COMMIT DROP AS
SELECT *
FROM dblink(:'oltp_conn', $$
    SELECT
        n.node_code,
        provider.email AS provider_email,
        ns.cpu_cores,
        ns.ram_gb,
        COALESCE(ns.gpu_model, 'CPU_ONLY') AS gpu_model,
        COALESCE(ns.gpu_vram_gb, 0) AS gpu_vram_gb,
        ns.disk_gb,
        np.price_cpu_hour,
        np.price_gpu_hour,
        np.price_ram_gb_hour
    FROM compute_marketplace.nodes n
    JOIN compute_marketplace.users provider
      ON provider.user_id = n.provider_user_id
    JOIN compute_marketplace.node_specs ns
      ON ns.node_id = n.node_id
    JOIN compute_marketplace.node_pricing np
      ON np.node_id = n.node_id
$$) AS t (
    node_code text,
    provider_email text,
    cpu_cores integer,
    ram_gb numeric(10, 2),
    gpu_model text,
    gpu_vram_gb numeric(10, 2),
    disk_gb numeric(10, 2),
    price_cpu_hour numeric(10, 2),
    price_gpu_hour numeric(10, 2),
    price_ram_gb_hour numeric(10, 2)
);

CREATE TEMP TABLE src_tasks ON COMMIT DROP AS
SELECT *
FROM dblink(:'oltp_conn', $$
    SELECT
        t.task_ref,
        buyer.email AS buyer_email,
        t.status_code,
        t.created_at,
        t.total_cost,
        tc.solver_type,
        tc.docker_image,
        tc.parameters_json::text,
        tc.estimated_cost,
        COUNT(j.job_id)::integer AS job_count
    FROM compute_marketplace.tasks t
    JOIN compute_marketplace.users buyer
      ON buyer.user_id = t.user_id
    JOIN compute_marketplace.task_configs tc
      ON tc.task_id = t.task_id
    LEFT JOIN compute_marketplace.jobs j
      ON j.task_id = t.task_id
    GROUP BY
        t.task_ref,
        buyer.email,
        t.status_code,
        t.created_at,
        t.total_cost,
        tc.solver_type,
        tc.docker_image,
        tc.parameters_json,
        tc.estimated_cost
$$) AS t (
    task_ref text,
    buyer_email text,
    status_code text,
    created_at timestamptz,
    total_cost numeric(14, 2),
    solver_type text,
    docker_image text,
    parameters_json text,
    estimated_cost numeric(14, 2),
    job_count integer
);

CREATE TEMP TABLE src_jobs ON COMMIT DROP AS
SELECT *
FROM dblink(:'oltp_conn', $$
    SELECT
        j.job_ref,
        t.task_ref,
        buyer.email AS buyer_email,
        provider.email AS provider_email,
        n.node_code,
        COALESCE(j.finished_at, j.started_at, j.created_at) AS event_ts,
        j.created_at,
        j.status_code AS job_status_code,
        COALESCE(v.status_code, 'not_checked') AS validation_status_code,
        COALESCE(EXTRACT(EPOCH FROM (COALESCE(j.finished_at, j.started_at, j.created_at) - COALESCE(j.started_at, j.created_at))) / 60.0, 0) AS runtime_minutes,
        COALESCE(jc.cpu_cost, 0) AS cpu_cost,
        COALESCE(jc.gpu_cost, 0) AS gpu_cost,
        COALESCE(jc.total_cost, 0) AS total_job_cost,
        COALESCE(AVG(jm.cpu_usage), 0) AS avg_cpu_usage,
        COALESCE(AVG(jm.gpu_usage), 0) AS avg_gpu_usage,
        COALESCE(AVG(jm.memory_usage), 0) AS avg_memory_usage,
        tc.solver_type,
        tc.docker_image,
        tc.parameters_json::text
    FROM compute_marketplace.jobs j
    JOIN compute_marketplace.tasks t
      ON t.task_id = j.task_id
    JOIN compute_marketplace.users buyer
      ON buyer.user_id = t.user_id
    JOIN compute_marketplace.task_configs tc
      ON tc.task_id = t.task_id
    LEFT JOIN compute_marketplace.nodes n
      ON n.node_id = j.node_id
    LEFT JOIN compute_marketplace.users provider
      ON provider.user_id = n.provider_user_id
    LEFT JOIN compute_marketplace.validations v
      ON v.job_id = j.job_id
    LEFT JOIN compute_marketplace.job_costs jc
      ON jc.job_id = j.job_id
    LEFT JOIN compute_marketplace.job_metrics jm
      ON jm.job_id = j.job_id
    GROUP BY
        j.job_ref,
        t.task_ref,
        buyer.email,
        provider.email,
        n.node_code,
        event_ts,
        j.created_at,
        j.status_code,
        v.status_code,
        runtime_minutes,
        jc.cpu_cost,
        jc.gpu_cost,
        jc.total_cost,
        tc.solver_type,
        tc.docker_image,
        tc.parameters_json
$$) AS t (
    job_ref text,
    task_ref text,
    buyer_email text,
    provider_email text,
    node_code text,
    event_ts timestamptz,
    created_at timestamptz,
    job_status_code text,
    validation_status_code text,
    runtime_minutes numeric(16, 4),
    cpu_cost numeric(14, 2),
    gpu_cost numeric(14, 2),
    total_job_cost numeric(14, 2),
    avg_cpu_usage numeric(10, 2),
    avg_gpu_usage numeric(10, 2),
    avg_memory_usage numeric(10, 2),
    solver_type text,
    docker_image text,
    parameters_json text
);

CREATE TEMP TABLE src_finance ON COMMIT DROP AS
SELECT *
FROM dblink(:'oltp_conn', $$
    SELECT
        t.created_at AS event_ts,
        u.email AS user_email,
        t.transaction_type_code AS event_code,
        t.amount
    FROM compute_marketplace.transactions t
    JOIN compute_marketplace.users u
      ON u.user_id = t.user_id
    UNION ALL
    SELECT
        p.created_at AS event_ts,
        u.email AS user_email,
        CASE p.payout_status_code
            WHEN 'pending' THEN 'payout_pending'
            ELSE 'payout_paid'
        END AS event_code,
        p.amount
    FROM compute_marketplace.payouts p
    JOIN compute_marketplace.users u
      ON u.user_id = p.provider_user_id
$$) AS t (
    event_ts timestamptz,
    user_email text,
    event_code text,
    amount numeric(14, 2)
);

INSERT INTO dim_organization (organization_name)
SELECT DISTINCT organization_name
FROM src_users
ON CONFLICT (organization_name) DO NOTHING;

CREATE TEMP TABLE src_user_dim ON COMMIT DROP AS
SELECT
    su.email AS user_nk,
    su.name AS user_name,
    su.role_code,
    org.organization_sk,
    su.created_at
FROM src_users su
LEFT JOIN dim_organization org
  ON org.organization_name = su.organization_name;

UPDATE dim_user_account_scd2 d
SET effective_from = s.created_at
FROM src_user_dim s
WHERE d.user_nk = s.user_nk
    AND d.is_current = true
    AND d.effective_from > s.created_at
    AND NOT EXISTS (
            SELECT 1
            FROM dim_user_account_scd2 older
            WHERE older.user_nk = d.user_nk
                AND older.user_sk <> d.user_sk
    );

UPDATE dim_user_account_scd2 d
SET
    effective_to = (SELECT batch_ts FROM etl_control),
    is_current = false
FROM src_user_dim s
WHERE d.user_nk = s.user_nk
  AND d.is_current = true
  AND (
      d.user_name IS DISTINCT FROM s.user_name
      OR d.role_code IS DISTINCT FROM s.role_code
      OR d.organization_sk IS DISTINCT FROM s.organization_sk
  );

INSERT INTO dim_user_account_scd2 (
    user_nk,
    user_name,
    role_code,
    organization_sk,
    effective_from,
    effective_to,
    is_current
)
SELECT
    s.user_nk,
    s.user_name,
    s.role_code,
    s.organization_sk,
    CASE
        WHEN d.user_sk IS NULL THEN s.created_at
        ELSE (SELECT batch_ts FROM etl_control)
    END,
    '9999-12-31 00:00:00+00'::timestamptz,
    true
FROM src_user_dim s
LEFT JOIN dim_user_account_scd2 d
  ON d.user_nk = s.user_nk
 AND d.is_current = true
WHERE d.user_sk IS NULL
   OR d.user_name IS DISTINCT FROM s.user_name
   OR d.role_code IS DISTINCT FROM s.role_code
   OR d.organization_sk IS DISTINCT FROM s.organization_sk;

INSERT INTO dim_user_account_scd2 (
    user_nk,
    user_name,
    role_code,
    organization_sk,
    effective_from,
    effective_to,
    is_current
)
VALUES (
    '__UNASSIGNED_PROVIDER__',
    'Unassigned Provider',
    'system',
    NULL,
    '1900-01-01 00:00:00+00'::timestamptz,
    '9999-12-31 00:00:00+00'::timestamptz,
    true
)
ON CONFLICT (user_nk, effective_from) DO NOTHING;

INSERT INTO dim_solver_family (solver_family_code, solver_family_name)
SELECT DISTINCT
    CASE
        WHEN solver_type IN ('OpenFOAM', 'SU2') THEN 'cfd'
        ELSE 'other'
    END AS solver_family_code,
    CASE
        WHEN solver_type IN ('OpenFOAM', 'SU2') THEN 'CFD Solvers'
        ELSE 'Other Solvers'
    END AS solver_family_name
FROM src_tasks
ON CONFLICT (solver_family_code) DO NOTHING;

INSERT INTO dim_solver (solver_type, solver_family_sk)
SELECT DISTINCT
    st.solver_type,
    sf.solver_family_sk
FROM src_tasks st
JOIN dim_solver_family sf
  ON sf.solver_family_code = CASE
      WHEN st.solver_type IN ('OpenFOAM', 'SU2') THEN 'cfd'
      ELSE 'other'
  END
ON CONFLICT (solver_type) DO UPDATE
SET solver_family_sk = EXCLUDED.solver_family_sk
WHERE dim_solver.solver_family_sk IS DISTINCT FROM EXCLUDED.solver_family_sk;

CREATE TEMP TABLE src_workloads ON COMMIT DROP AS
SELECT DISTINCT
    md5(st.solver_type || '|' || st.docker_image || '|' || st.parameters_json) AS workload_nk,
    st.solver_type,
    st.docker_image,
    left(md5(st.parameters_json), 12) AS parameter_signature,
    CASE
        WHEN st.estimated_cost < 50 THEN 'low'
        WHEN st.estimated_cost < 150 THEN 'medium'
        ELSE 'high'
    END AS estimated_cost_band,
    st.parameters_json::jsonb AS parameters_jsonb
FROM src_tasks st;

INSERT INTO dim_workload_profile (
    workload_nk,
    solver_sk,
    docker_image,
    parameter_signature,
    estimated_cost_band
)
SELECT
    sw.workload_nk,
    ds.solver_sk,
    sw.docker_image,
    sw.parameter_signature,
    sw.estimated_cost_band
FROM src_workloads sw
JOIN dim_solver ds
  ON ds.solver_type = sw.solver_type
ON CONFLICT (workload_nk) DO UPDATE
SET
    solver_sk = EXCLUDED.solver_sk,
    docker_image = EXCLUDED.docker_image,
    parameter_signature = EXCLUDED.parameter_signature,
    estimated_cost_band = EXCLUDED.estimated_cost_band
WHERE
    dim_workload_profile.solver_sk IS DISTINCT FROM EXCLUDED.solver_sk
    OR dim_workload_profile.docker_image IS DISTINCT FROM EXCLUDED.docker_image
    OR dim_workload_profile.parameter_signature IS DISTINCT FROM EXCLUDED.parameter_signature
    OR dim_workload_profile.estimated_cost_band IS DISTINCT FROM EXCLUDED.estimated_cost_band;

INSERT INTO dim_parameter_tag (tag_key, tag_value, tag_label)
SELECT DISTINCT
    jt.key,
    jt.value,
    jt.key || '=' || jt.value
FROM src_workloads sw
CROSS JOIN LATERAL jsonb_each_text(sw.parameters_jsonb) AS jt(key, value)
ON CONFLICT (tag_key, tag_value) DO NOTHING;

INSERT INTO bridge_workload_parameter_tag (workload_sk, parameter_tag_sk, allocation_weight)
SELECT DISTINCT
    dwp.workload_sk,
    dpt.parameter_tag_sk,
    1
FROM src_workloads sw
JOIN dim_workload_profile dwp
  ON dwp.workload_nk = sw.workload_nk
CROSS JOIN LATERAL jsonb_each_text(sw.parameters_jsonb) AS jt(key, value)
JOIN dim_parameter_tag dpt
  ON dpt.tag_key = jt.key
 AND dpt.tag_value = jt.value
ON CONFLICT (workload_sk, parameter_tag_sk) DO NOTHING;

INSERT INTO dim_gpu_family (gpu_family_name)
SELECT DISTINCT
    CASE
        WHEN gpu_model LIKE '%H100%' THEN 'Hopper'
        WHEN gpu_model LIKE '%A100%' THEN 'Ampere Datacenter'
        WHEN gpu_model LIKE '%RTX%' THEN 'RTX Professional'
        WHEN gpu_model = 'CPU_ONLY' THEN 'CPU Only'
        ELSE 'Other GPU'
    END AS gpu_family_name
FROM src_nodes
ON CONFLICT (gpu_family_name) DO NOTHING;

INSERT INTO dim_node (
    node_nk,
    gpu_family_sk,
    gpu_model,
    cpu_cores,
    ram_gb,
    gpu_vram_gb,
    disk_gb,
    performance_tier,
    price_band
)
SELECT
    sn.node_code,
    dgf.gpu_family_sk,
    sn.gpu_model,
    sn.cpu_cores,
    sn.ram_gb,
    sn.gpu_vram_gb,
    sn.disk_gb,
    CASE
        WHEN sn.cpu_cores >= 64 OR sn.gpu_model LIKE '%H100%' THEN 'premium'
        WHEN sn.cpu_cores >= 32 OR sn.gpu_model LIKE '%A100%' THEN 'standard'
        ELSE 'entry'
    END AS performance_tier,
    CASE
        WHEN sn.price_gpu_hour >= 5 OR sn.price_cpu_hour >= 2.5 THEN 'high'
        WHEN sn.price_gpu_hour >= 3 OR sn.price_cpu_hour >= 1.5 THEN 'medium'
        ELSE 'low'
    END AS price_band
FROM src_nodes sn
JOIN dim_gpu_family dgf
  ON dgf.gpu_family_name = CASE
      WHEN sn.gpu_model LIKE '%H100%' THEN 'Hopper'
      WHEN sn.gpu_model LIKE '%A100%' THEN 'Ampere Datacenter'
      WHEN sn.gpu_model LIKE '%RTX%' THEN 'RTX Professional'
      WHEN sn.gpu_model = 'CPU_ONLY' THEN 'CPU Only'
      ELSE 'Other GPU'
  END
ON CONFLICT (node_nk) DO UPDATE
SET
    gpu_family_sk = EXCLUDED.gpu_family_sk,
    gpu_model = EXCLUDED.gpu_model,
    cpu_cores = EXCLUDED.cpu_cores,
    ram_gb = EXCLUDED.ram_gb,
    gpu_vram_gb = EXCLUDED.gpu_vram_gb,
    disk_gb = EXCLUDED.disk_gb,
    performance_tier = EXCLUDED.performance_tier,
    price_band = EXCLUDED.price_band
WHERE
    dim_node.gpu_family_sk IS DISTINCT FROM EXCLUDED.gpu_family_sk
    OR dim_node.gpu_model IS DISTINCT FROM EXCLUDED.gpu_model
    OR dim_node.cpu_cores IS DISTINCT FROM EXCLUDED.cpu_cores
    OR dim_node.ram_gb IS DISTINCT FROM EXCLUDED.ram_gb
    OR dim_node.gpu_vram_gb IS DISTINCT FROM EXCLUDED.gpu_vram_gb
    OR dim_node.disk_gb IS DISTINCT FROM EXCLUDED.disk_gb
    OR dim_node.performance_tier IS DISTINCT FROM EXCLUDED.performance_tier
    OR dim_node.price_band IS DISTINCT FROM EXCLUDED.price_band;

INSERT INTO dim_node (
    node_nk,
    gpu_family_sk,
    gpu_model,
    cpu_cores,
    ram_gb,
    gpu_vram_gb,
    disk_gb,
    performance_tier,
    price_band
)
VALUES (
    '__UNASSIGNED_NODE__',
    NULL,
    'UNASSIGNED',
    0,
    0,
    0,
    0,
    'unassigned',
    'unassigned'
)
ON CONFLICT (node_nk) DO NOTHING;

INSERT INTO dim_date (
    date_key,
    full_date,
    day_of_week,
    day_name,
    day_of_month,
    month_number,
    month_name,
    quarter_number,
    year_number,
    week_of_year,
    is_weekend
)
SELECT DISTINCT
    to_char(src_date, 'YYYYMMDD')::integer AS date_key,
    src_date,
    extract(isodow FROM src_date)::integer AS day_of_week,
    to_char(src_date, 'FMDay') AS day_name,
    extract(day FROM src_date)::integer AS day_of_month,
    extract(month FROM src_date)::integer AS month_number,
    to_char(src_date, 'FMMonth') AS month_name,
    extract(quarter FROM src_date)::integer AS quarter_number,
    extract(year FROM src_date)::integer AS year_number,
    extract(week FROM src_date)::integer AS week_of_year,
    extract(isodow FROM src_date) IN (6, 7) AS is_weekend
FROM (
    SELECT created_at::date AS src_date FROM src_tasks
    UNION
    SELECT event_ts::date AS src_date FROM src_jobs
    UNION
    SELECT event_ts::date AS src_date FROM src_finance
) d
ON CONFLICT (date_key) DO NOTHING;

CREATE TEMP TABLE agg_task_daily ON COMMIT DROP AS
SELECT
    to_char(st.created_at::date, 'YYYYMMDD')::integer AS date_key,
    buyer.user_sk AS buyer_user_sk,
    dwp.workload_sk,
    dts.task_status_sk,
    COUNT(*)::integer AS tasks_created_count,
    COALESCE(SUM(st.job_count), 0)::integer AS jobs_requested_count,
    COALESCE(SUM(st.estimated_cost), 0)::numeric(14, 2) AS total_estimated_cost,
    COALESCE(SUM(st.total_cost), 0)::numeric(14, 2) AS total_actual_cost,
    SUM(CASE WHEN st.status_code = 'completed' THEN 1 ELSE 0 END)::integer AS completed_tasks_count,
    SUM(CASE WHEN st.status_code = 'failed' THEN 1 ELSE 0 END)::integer AS failed_tasks_count
FROM src_tasks st
JOIN dim_user_account_scd2 buyer
  ON buyer.user_nk = st.buyer_email
 AND st.created_at >= buyer.effective_from
 AND st.created_at < buyer.effective_to
JOIN dim_task_status dts
  ON dts.status_code = st.status_code
JOIN dim_workload_profile dwp
  ON dwp.workload_nk = md5(st.solver_type || '|' || st.docker_image || '|' || st.parameters_json)
GROUP BY
    to_char(st.created_at::date, 'YYYYMMDD')::integer,
    buyer.user_sk,
    dwp.workload_sk,
    dts.task_status_sk;

INSERT INTO fact_task_daily (
    date_key,
    buyer_user_sk,
    workload_sk,
    task_status_sk,
    tasks_created_count,
    jobs_requested_count,
    total_estimated_cost,
    total_actual_cost,
    completed_tasks_count,
    failed_tasks_count
)
SELECT
    date_key,
    buyer_user_sk,
    workload_sk,
    task_status_sk,
    tasks_created_count,
    jobs_requested_count,
    total_estimated_cost,
    total_actual_cost,
    completed_tasks_count,
    failed_tasks_count
FROM agg_task_daily
ON CONFLICT (date_key, buyer_user_sk, workload_sk, task_status_sk) DO UPDATE
SET
    tasks_created_count = EXCLUDED.tasks_created_count,
    jobs_requested_count = EXCLUDED.jobs_requested_count,
    total_estimated_cost = EXCLUDED.total_estimated_cost,
    total_actual_cost = EXCLUDED.total_actual_cost,
    completed_tasks_count = EXCLUDED.completed_tasks_count,
    failed_tasks_count = EXCLUDED.failed_tasks_count
WHERE
    fact_task_daily.tasks_created_count IS DISTINCT FROM EXCLUDED.tasks_created_count
    OR fact_task_daily.jobs_requested_count IS DISTINCT FROM EXCLUDED.jobs_requested_count
    OR fact_task_daily.total_estimated_cost IS DISTINCT FROM EXCLUDED.total_estimated_cost
    OR fact_task_daily.total_actual_cost IS DISTINCT FROM EXCLUDED.total_actual_cost
    OR fact_task_daily.completed_tasks_count IS DISTINCT FROM EXCLUDED.completed_tasks_count
    OR fact_task_daily.failed_tasks_count IS DISTINCT FROM EXCLUDED.failed_tasks_count;

CREATE TEMP TABLE agg_job_daily ON COMMIT DROP AS
SELECT
    to_char(sj.event_ts::date, 'YYYYMMDD')::integer AS date_key,
    buyer.user_sk AS buyer_user_sk,
    provider.user_sk AS provider_user_sk,
    dn.node_sk,
    dwp.workload_sk,
    djo.job_outcome_sk,
    COUNT(*)::integer AS jobs_count,
    COALESCE(SUM(sj.runtime_minutes), 0)::numeric(16, 2) AS total_runtime_minutes,
    COALESCE(SUM(sj.cpu_cost), 0)::numeric(14, 2) AS total_cpu_cost,
    COALESCE(SUM(sj.gpu_cost), 0)::numeric(14, 2) AS total_gpu_cost,
    COALESCE(SUM(sj.total_job_cost), 0)::numeric(14, 2) AS total_job_cost,
    AVG(sj.avg_cpu_usage)::numeric(10, 2) AS avg_cpu_usage,
    AVG(sj.avg_gpu_usage)::numeric(10, 2) AS avg_gpu_usage,
    AVG(sj.avg_memory_usage)::numeric(10, 2) AS avg_memory_usage
FROM src_jobs sj
JOIN dim_user_account_scd2 buyer
  ON buyer.user_nk = sj.buyer_email
 AND sj.event_ts >= buyer.effective_from
 AND sj.event_ts < buyer.effective_to
LEFT JOIN dim_user_account_scd2 provider
    ON provider.user_nk = COALESCE(sj.provider_email, '__UNASSIGNED_PROVIDER__')
 AND sj.event_ts >= provider.effective_from
 AND sj.event_ts < provider.effective_to
LEFT JOIN dim_node dn
    ON dn.node_nk = COALESCE(sj.node_code, '__UNASSIGNED_NODE__')
JOIN dim_workload_profile dwp
  ON dwp.workload_nk = md5(sj.solver_type || '|' || sj.docker_image || '|' || sj.parameters_json)
JOIN dim_job_outcome djo
  ON djo.job_status_code = sj.job_status_code
 AND djo.validation_status_code = sj.validation_status_code
GROUP BY
    to_char(sj.event_ts::date, 'YYYYMMDD')::integer,
    buyer.user_sk,
    provider.user_sk,
    dn.node_sk,
    dwp.workload_sk,
    djo.job_outcome_sk;

INSERT INTO fact_job_execution_daily (
    date_key,
    buyer_user_sk,
    provider_user_sk,
    node_sk,
    workload_sk,
    job_outcome_sk,
    jobs_count,
    total_runtime_minutes,
    total_cpu_cost,
    total_gpu_cost,
    total_job_cost,
    avg_cpu_usage,
    avg_gpu_usage,
    avg_memory_usage
)
SELECT
    date_key,
    buyer_user_sk,
    provider_user_sk,
    node_sk,
    workload_sk,
    job_outcome_sk,
    jobs_count,
    total_runtime_minutes,
    total_cpu_cost,
    total_gpu_cost,
    total_job_cost,
    avg_cpu_usage,
    avg_gpu_usage,
    avg_memory_usage
FROM agg_job_daily
ON CONFLICT (date_key, buyer_user_sk, provider_user_sk, node_sk, workload_sk, job_outcome_sk) DO UPDATE
SET
    jobs_count = EXCLUDED.jobs_count,
    total_runtime_minutes = EXCLUDED.total_runtime_minutes,
    total_cpu_cost = EXCLUDED.total_cpu_cost,
    total_gpu_cost = EXCLUDED.total_gpu_cost,
    total_job_cost = EXCLUDED.total_job_cost,
    avg_cpu_usage = EXCLUDED.avg_cpu_usage,
    avg_gpu_usage = EXCLUDED.avg_gpu_usage,
    avg_memory_usage = EXCLUDED.avg_memory_usage
WHERE
    fact_job_execution_daily.jobs_count IS DISTINCT FROM EXCLUDED.jobs_count
    OR fact_job_execution_daily.total_runtime_minutes IS DISTINCT FROM EXCLUDED.total_runtime_minutes
    OR fact_job_execution_daily.total_cpu_cost IS DISTINCT FROM EXCLUDED.total_cpu_cost
    OR fact_job_execution_daily.total_gpu_cost IS DISTINCT FROM EXCLUDED.total_gpu_cost
    OR fact_job_execution_daily.total_job_cost IS DISTINCT FROM EXCLUDED.total_job_cost
    OR fact_job_execution_daily.avg_cpu_usage IS DISTINCT FROM EXCLUDED.avg_cpu_usage
    OR fact_job_execution_daily.avg_gpu_usage IS DISTINCT FROM EXCLUDED.avg_gpu_usage
    OR fact_job_execution_daily.avg_memory_usage IS DISTINCT FROM EXCLUDED.avg_memory_usage;

CREATE TEMP TABLE agg_finance_daily ON COMMIT DROP AS
SELECT
    to_char(sf.event_ts::date, 'YYYYMMDD')::integer AS date_key,
    du.user_sk,
    dfe.finance_event_sk,
    COUNT(*)::integer AS event_count,
    COALESCE(SUM(sf.amount), 0)::numeric(14, 2) AS total_amount
FROM src_finance sf
JOIN dim_user_account_scd2 du
  ON du.user_nk = sf.user_email
 AND sf.event_ts >= du.effective_from
 AND sf.event_ts < du.effective_to
JOIN dim_finance_event dfe
  ON dfe.finance_event_code = sf.event_code
GROUP BY
    to_char(sf.event_ts::date, 'YYYYMMDD')::integer,
    du.user_sk,
    dfe.finance_event_sk;

INSERT INTO fact_finance_daily (
    date_key,
    user_sk,
    finance_event_sk,
    event_count,
    total_amount
)
SELECT
    date_key,
    user_sk,
    finance_event_sk,
    event_count,
    total_amount
FROM agg_finance_daily
ON CONFLICT (date_key, user_sk, finance_event_sk) DO UPDATE
SET
    event_count = EXCLUDED.event_count,
    total_amount = EXCLUDED.total_amount
WHERE
    fact_finance_daily.event_count IS DISTINCT FROM EXCLUDED.event_count
    OR fact_finance_daily.total_amount IS DISTINCT FROM EXCLUDED.total_amount;

COMMIT;