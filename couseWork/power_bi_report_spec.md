# Compute Marketplace Power BI Report

## Title

Compute Marketplace Performance Overview

## Data source

Use the OLAP database `compute_marketplace_olap` and import these reporting views from schema `marketplace_dw`:

- `vw_powerbi_task_summary`
- `vw_powerbi_job_execution`
- `vw_powerbi_finance`

## Required slicers

1. `full_date` at month granularity from `vw_powerbi_job_execution`
2. `solver_family_name` from `vw_powerbi_job_execution`
3. `provider_organization` from `vw_powerbi_job_execution`

## Visuals

1. Clustered column chart: `full_date` by week on X-axis, `SUM(total_job_cost)` on Y-axis, legend by `solver_family_name`
2. Donut chart: values `SUM(jobs_count)`, legend `outcome_label`
3. Horizontal bar chart: axis `provider_organization`, value `SUM(total_amount)` filtered to `finance_event_group = Provider Payouts`
4. Line chart: axis `full_date`, values `SUM(tasks_created_count)` and `SUM(total_actual_cost)`
5. KPI cards: `SUM(total_job_cost)`, `SUM(jobs_count)`, `AVERAGE(total_runtime_minutes)`

## Suggested DAX measures

```DAX
Total Job Cost = SUM(vw_powerbi_job_execution[total_job_cost])

Completed Jobs =
CALCULATE(
    SUM(vw_powerbi_job_execution[jobs_count]),
    vw_powerbi_job_execution[outcome_label] = "Completed and valid"
)

Average Runtime Minutes =
DIVIDE(
    SUM(vw_powerbi_job_execution[total_runtime_minutes]),
    SUM(vw_powerbi_job_execution[jobs_count])
)

Provider Payout Amount =
CALCULATE(
    SUM(vw_powerbi_finance[total_amount]),
    vw_powerbi_finance[finance_event_group] = "Provider Payouts"
)

Task Failure Rate =
DIVIDE(
    SUM(vw_powerbi_task_summary[failed_tasks_count]),
    SUM(vw_powerbi_task_summary[tasks_created_count])
)
```

## Layout note

The matching wireframe is available in `power_bi_report_wireframe.svg`.