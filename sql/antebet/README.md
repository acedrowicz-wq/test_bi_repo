# Antebet report on ClickHouse (ProdCH)

| Step | File | How to run it | When |
|---|---|---|---|
| 0 | `00_definer_user.sql` | SQL console | before anything else (optionally test it all on StagePlatformCH first) |
| 1 | `01_tables.sql` | SQL console / `clickhouse client` | any time |
| 2 | `02_incremental_mvs.sql` | SQL console / `clickhouse client` | **before** `<CUTOFF>` |
| 3+4 | `03_backfill_rounds.sql`, `04_backfill_report.sql` | `./run_backfill.sh '<CUTOFF>'` | **after** `<CUTOFF>` + 15 min |
| 5 | `05_refreshable_mvs_and_view.sql` | SQL console / `clickhouse client` | after the backfill |
| 6 | — | point Tableau at `adam_sandbox.bi_antebet_report_v` | after the first refresh |

`<CUTOFF>` = a Warsaw midnight written in UTC (22:00 in summer time, 23:00 in winter time).
It is now `2026-10-05 22:00:00`. If you create the MVs later, change it in both places in `02_incremental_mvs.sql`.

## Permissions (step 0)
The account that creates the objects needs CREATE, SELECT, INSERT, dictGet, CREATE USER and
SET DEFINER (all of these are in the console grants of a.cedrowicz, WITH GRANT OPTION).
All MVs run as `bi_antebet_definer` (`00_definer_user.sql`), not as the creator:
the console JWT user is not a permanent account, and an error in an MV on `platform.slot_actions`
would stop PeerDB replication (`mysql_slot_actions_mv` -> `slot_actions`).

The Tableau account must have `SELECT ON adam_sandbox.*` (the `bi_antebet_report_v` view runs as the reader).

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
The SQL console login (JWT) does not work in `clickhouse client`: for the terminal, use credentials
from Vault (like the `v-oidc-*` users) or another password-based account with SELECT/INSERT on `adam_sandbox.*`
and SELECT on the `platform` sources. Steps 0, 1, 2 and 5 can just as well be run in the SQL console.

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
-- DROP USER IF EXISTS bi_antebet_definer;   -- only after the MVs are dropped
-- then optionally the tables: bi_antebet_rounds, bi_antebet_report, bi_antebet_report_recent
```
