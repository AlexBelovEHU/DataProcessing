SET search_path = marketplace_dw, public;

-- Query 1: Monthly demand and realized cost by solver family.
SELECT
    dd.year_number,
    dd.month_number,
    dd.month_name,
    sf.solver_family_name,
    SUM(ftd.tasks_created_count) AS tasks_created,
    SUM(ftd.jobs_requested_count) AS jobs_requested,
    ROUND(SUM(ftd.total_estimated_cost), 2) AS estimated_cost,
    ROUND(SUM(ftd.total_actual_cost), 2) AS actual_cost,
    ROUND(SUM(ftd.total_actual_cost) - SUM(ftd.total_estimated_cost), 2) AS cost_variance
FROM fact_task_daily ftd
JOIN dim_date dd
  ON dd.date_key = ftd.date_key
JOIN dim_workload_profile dwp
  ON dwp.workload_sk = ftd.workload_sk
JOIN dim_solver ds
  ON ds.solver_sk = dwp.solver_sk
JOIN dim_solver_family sf
  ON sf.solver_family_sk = ds.solver_family_sk
GROUP BY
    dd.year_number,
    dd.month_number,
    dd.month_name,
    sf.solver_family_name
ORDER BY dd.year_number, dd.month_number, actual_cost DESC;

-- Query 2: Provider-side execution efficiency by organization and node tier.
SELECT
    provider_org.organization_name AS provider_organization,
    dn.performance_tier,
    djo.outcome_label,
    SUM(fje.jobs_count) AS jobs_count,
    ROUND(SUM(fje.total_job_cost), 2) AS total_job_cost,
    ROUND(AVG(fje.avg_cpu_usage), 2) AS avg_cpu_usage,
    ROUND(AVG(fje.avg_gpu_usage), 2) AS avg_gpu_usage,
    ROUND(AVG(fje.total_runtime_minutes), 2) AS avg_runtime_minutes_per_group
FROM fact_job_execution_daily fje
LEFT JOIN dim_user_account_scd2 provider
  ON provider.user_sk = fje.provider_user_sk
LEFT JOIN dim_organization provider_org
  ON provider_org.organization_sk = provider.organization_sk
LEFT JOIN dim_node dn
  ON dn.node_sk = fje.node_sk
JOIN dim_job_outcome djo
  ON djo.job_outcome_sk = fje.job_outcome_sk
GROUP BY
    provider_org.organization_name,
    dn.performance_tier,
    djo.outcome_label
ORDER BY total_job_cost DESC, jobs_count DESC;

-- Query 3: Parameter-tag analysis through the bridge table.
SELECT
    sf.solver_family_name,
    dpt.tag_key,
    dpt.tag_value,
    SUM(fje.jobs_count) AS jobs_count,
    ROUND(SUM(fje.total_job_cost), 2) AS total_job_cost,
    ROUND(SUM(fje.total_runtime_minutes), 2) AS total_runtime_minutes
FROM fact_job_execution_daily fje
JOIN dim_workload_profile dwp
  ON dwp.workload_sk = fje.workload_sk
JOIN dim_solver ds
  ON ds.solver_sk = dwp.solver_sk
JOIN dim_solver_family sf
  ON sf.solver_family_sk = ds.solver_family_sk
JOIN bridge_workload_parameter_tag bwpt
  ON bwpt.workload_sk = dwp.workload_sk
JOIN dim_parameter_tag dpt
  ON dpt.parameter_tag_sk = bwpt.parameter_tag_sk
GROUP BY
    sf.solver_family_name,
    dpt.tag_key,
    dpt.tag_value
ORDER BY total_job_cost DESC, jobs_count DESC;

-- Query 4: SCD Type 2 history of user organization and role changes.
SELECT
    dus.user_nk AS user_email,
    dus.user_name,
    dus.role_code,
    org.organization_name,
    dus.effective_from,
    dus.effective_to,
    dus.is_current
FROM dim_user_account_scd2 dus
LEFT JOIN dim_organization org
  ON org.organization_sk = dus.organization_sk
ORDER BY dus.user_nk, dus.effective_from;

-- Query 5: Net finance movement by day and event type.
SELECT
    dd.full_date,
    dfe.finance_event_group,
    dfe.finance_event_code,
    dfe.flow_direction,
    SUM(ffd.event_count) AS event_count,
    ROUND(SUM(ffd.total_amount), 2) AS total_amount
FROM fact_finance_daily ffd
JOIN dim_date dd
  ON dd.date_key = ffd.date_key
JOIN dim_finance_event dfe
  ON dfe.finance_event_sk = ffd.finance_event_sk
GROUP BY
    dd.full_date,
    dfe.finance_event_group,
    dfe.finance_event_code,
    dfe.flow_direction
ORDER BY dd.full_date, dfe.finance_event_group, dfe.finance_event_code;