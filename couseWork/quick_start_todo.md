# Quick Start ToDo

## pgAdmin

1. Open pgAdmin and connect to your PostgreSQL server.
2. Create or choose an OLTP database for the transactional layer.
3. Run `init_compute_marketplace_oltp.sql` in the Query Tool.
4. In `load_compute_marketplace_oltp.sql`, update the CSV paths if needed, or run it from the `couseWork` folder so `./data/...` resolves correctly.
5. Run `load_compute_marketplace_oltp.sql` to load the OLTP sample data.
6. Run `init_compute_marketplace_olap.sql` to create the separate OLAP database `compute_marketplace_olap`.
7. Open the OLAP database in pgAdmin and run `etl_oltp_to_olap.sql`.
8. If your OLTP database name is not `compute_marketplace_oltp`, update the connection string inside `etl_oltp_to_olap.sql` before running it.
9. Optionally run `oltp_insight_queries.sql` and `olap_insight_queries.sql` to verify the data and view the insights.

## Power BI

1. Open Power BI Desktop.
2. Get Data from PostgreSQL.
3. Connect to the `compute_marketplace_olap` database.
4. Import these views from schema `marketplace_dw`:
   `vw_powerbi_task_summary`, `vw_powerbi_job_execution`, `vw_powerbi_finance`.
5. In Power Query, check data types and apply any small cleanup you need.
6. Add the report title: `Compute Marketplace Performance Overview`.
7. Add at least 2 slicers. Recommended: `full_date` by month, `solver_family_name`, `provider_organization`.
8. Add at least 3 visuals. Recommended: clustered column chart, donut chart, bar chart, line chart, and KPI cards.
9. Use `power_bi_report_spec.md` and `power_bi_report_wireframe.svg` as the layout guide.