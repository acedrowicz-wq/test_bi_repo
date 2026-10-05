# Antebet report on ClickHouse (ProdCH)

| Step | File | How to run it | When |
|---|---|---|---|
| 0 | — | check permissions (below), test on StagePlatformCH | before anything else |
| 1 | `01_tables.sql` | SQL console / `clickhouse client` | any time |
| 2 | `02_incremental_mvs.sql` | SQL console / `clickhouse client` | **before** `<CUTOFF>` |
| 3+4 | `03_backfill_rounds.sql`, `04_backfill_report.sql` | `./run_backfill.sh '<CUTOFF>'` | **after** `<CUTOFF>` + 15 min |
| 5 | `05_refreshable_mvs_and_view.sql` | SQL console / `clickhouse client` | after the backfill |
| 6 | — | point Tableau at `adam_sandbox.bi_antebet_report_v` | after the first refresh |

`<CUTOFF>` = a Warsaw midnight written in UTC (22:00 in summer time, 23:00 in winter time).
It is now `2026-10-05 22:00:00`. If you create the MVs later, change it in both places in `02_incremental_mvs.sql`.

## Permissions (step 0)
The user who creates the objects needs: `CREATE DATABASE` (or an existing `adam_sandbox`),
`CREATE TABLE / VIEW` on `adam_sandbox.*`, `SELECT` on `platform.slot_actions`,
`platform.mysql_slot_actions_extra`, `dictGet` on `platform.currency_d` and `platform.whitelabels_d`.
The MVs run as their creator (SQL SECURITY DEFINER), so these permissions have to stay in place.

```sql
SHOW GRANTS;
```

## Running from the terminal
```bash
export CH_HOST=hyxzs78gz1.europe-west4.gcp.clickhouse.cloud CH_USER=... CH_PASSWORD=...
clickhouse client --host $CH_HOST --secure --user $CH_USER --password $CH_PASSWORD --queries-file 01_tables.sql
clickhouse client --host $CH_HOST --secure --user $CH_USER --password $CH_PASSWORD --queries-file 02_incremental_mvs.sql
# ... after <CUTOFF> + 15 min:
./run_backfill.sh '2026-10-05 22:00:00'
clickhouse client --host $CH_HOST --secure --user $CH_USER --password $CH_PASSWORD --queries-file 05_refreshable_mvs_and_view.sql
```
Your IP must be on the ProdCH IP Access List (e.g. through WARP VPN).

## Checks
```sql
-- are the MVs writing (after <CUTOFF>)?
SELECT action_date, count(), sum(actions_cnt), countIf(ante_bet > 0)
FROM adam_sandbox.bi_antebet_rounds GROUP BY action_date ORDER BY action_date DESC LIMIT 5;

-- refreshable MV status
SELECT view, status, last_success_time, next_refresh_time, exception
FROM system.view_refreshes WHERE database = 'adam_sandbox';

-- compare with the original script for one closed day
SELECT spin_category, sum(total_rounds), sum(total_bet_amount), sum(total_win)
FROM adam_sandbox.bi_antebet_report_v WHERE report_date = today() - 3
GROUP BY spin_category ORDER BY spin_category;
```

## Rollback (MVs first: they sit on the production insert path)
```sql
DROP VIEW IF EXISTS adam_sandbox.bi_antebet_rounds_mv;
DROP VIEW IF EXISTS adam_sandbox.bi_antebet_rounds_extra_mv;
DROP VIEW IF EXISTS adam_sandbox.bi_antebet_mv;
DROP VIEW IF EXISTS adam_sandbox.bi_antebet_recent_mv;
DROP VIEW IF EXISTS adam_sandbox.bi_antebet_report_v;
-- then optionally the tables: bi_antebet_rounds, bi_antebet_report, bi_antebet_report_recent
```
