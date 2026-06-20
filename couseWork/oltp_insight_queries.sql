SET search_path = compute_marketplace, public;

-- Query 1: Buyer task pipeline and spend by solver.
SELECT
    u.email AS buyer_email,
    p.name AS buyer_name,
    tc.solver_type,
    COUNT(DISTINCT t.task_id) AS task_count,
    COUNT(j.job_id) AS job_count,
    SUM(CASE WHEN j.status_code = 'completed' THEN 1 ELSE 0 END) AS completed_jobs,
    SUM(CASE WHEN j.status_code = 'failed' THEN 1 ELSE 0 END) AS failed_jobs,
    ROUND(SUM(COALESCE(jc.total_cost, 0)), 2) AS realized_job_cost,
    ROUND(AVG(tc.estimated_cost), 2) AS avg_estimated_task_cost
FROM tasks t
JOIN users u
  ON u.user_id = t.user_id
JOIN profiles p
  ON p.user_id = u.user_id
JOIN task_configs tc
  ON tc.task_id = t.task_id
LEFT JOIN jobs j
  ON j.task_id = t.task_id
LEFT JOIN job_costs jc
  ON jc.job_id = j.job_id
GROUP BY
    u.email,
    p.name,
    tc.solver_type
ORDER BY realized_job_cost DESC, task_count DESC;

-- Query 2: Provider node utilization, quality, and earnings exposure.
SELECT
    provider.email AS provider_email,
    provider_profile.organization,
    n.node_code,
    n.status_code AS current_node_status,
    COUNT(j.job_id) AS assigned_jobs,
    SUM(CASE WHEN j.status_code = 'running' THEN 1 ELSE 0 END) AS running_jobs,
    SUM(CASE WHEN v.status_code = 'invalid' THEN 1 ELSE 0 END) AS invalidated_jobs,
    ROUND(AVG(EXTRACT(EPOCH FROM (COALESCE(j.finished_at, j.started_at, j.created_at) - COALESCE(j.started_at, j.created_at))) / 60.0), 2) AS avg_runtime_minutes,
    ROUND(SUM(COALESCE(jc.total_cost, 0)), 2) AS total_compute_revenue
FROM nodes n
JOIN users provider
  ON provider.user_id = n.provider_user_id
JOIN profiles provider_profile
  ON provider_profile.user_id = provider.user_id
LEFT JOIN jobs j
  ON j.node_id = n.node_id
LEFT JOIN validations v
  ON v.job_id = j.job_id
LEFT JOIN job_costs jc
  ON jc.job_id = j.job_id
GROUP BY
    provider.email,
    provider_profile.organization,
    n.node_code,
    n.status_code
ORDER BY total_compute_revenue DESC, assigned_jobs DESC;

-- Query 3: Financial position of buyers and providers.
SELECT
    u.email,
    p.name,
    u.role_code,
    p.balance AS current_balance,
    ROUND(SUM(CASE WHEN tr.transaction_type_code = 'credit' THEN tr.amount ELSE 0 END), 2) AS total_credits,
    ROUND(SUM(CASE WHEN tr.transaction_type_code = 'debit' THEN tr.amount ELSE 0 END), 2) AS total_debits,
    ROUND(SUM(CASE WHEN po.payout_status_code = 'pending' THEN po.amount ELSE 0 END), 2) AS pending_payout_amount,
    ROUND(SUM(CASE WHEN po.payout_status_code = 'paid' THEN po.amount ELSE 0 END), 2) AS paid_payout_amount
FROM users u
JOIN profiles p
  ON p.user_id = u.user_id
LEFT JOIN transactions tr
  ON tr.user_id = u.user_id
LEFT JOIN payouts po
  ON po.provider_user_id = u.user_id
GROUP BY
    u.email,
    p.name,
    u.role_code,
    p.balance
ORDER BY
    u.role_code,
    current_balance DESC,
    total_debits DESC NULLS LAST;

-- Query 4: Jobs with quality risk or missing validation details.
SELECT
    j.job_ref,
    t.task_ref,
    buyer.email AS buyer_email,
    n.node_code,
    j.status_code AS job_status,
    COALESCE(v.status_code, 'not_checked') AS validation_status,
    v.reason,
    jr.output_path,
    jr.checksum,
    j.created_at,
    j.finished_at
FROM jobs j
JOIN tasks t
  ON t.task_id = j.task_id
JOIN users buyer
  ON buyer.user_id = t.user_id
LEFT JOIN nodes n
  ON n.node_id = j.node_id
LEFT JOIN validations v
  ON v.job_id = j.job_id
LEFT JOIN job_results jr
  ON jr.job_id = j.job_id
WHERE j.status_code IN ('failed', 'completed')
  AND (
      COALESCE(v.status_code, 'not_checked') <> 'valid'
      OR jr.checksum IS NULL
  )
ORDER BY j.created_at DESC;