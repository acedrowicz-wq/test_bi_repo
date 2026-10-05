# Antebet report on ClickHouse (ProdCH)

You run everything ONCE, in the SQL console, before `<CUTOFF>` (now `2026-10-05 22:00:00` UTC
= midnight Warsaw time on 06.10). After that everything works by itself:

| What | Object | How often |
|---|---|---|
| new rounds | `bi_antebet_rounds_mv`, `bi_antebet_rounds_extra_mv` | on every insert (real time) |
| history 20.08 -> 05.10 | `bi_antebet_backfill_mv` | 1 day/min, starts by itself at 22:15 UTC, done after ~1 h |
| closed days | `bi_antebet_mv` -> `bi_antebet_report` | every 15 min (history ~4 h after the backfill, then +1 day after midnight) |
| today + yesterday | `bi_antebet_recent_mv` -> `bi_antebet_report_recent` | every 15 min |
| Tableau | `bi_antebet_report_v` | — |

Files, in order: `00_definer_user.sql`, `01_tables.sql`, `02_incremental_mvs.sql`,
`03_backfill_mv.sql`, `04_report_mvs_and_view.sql`.

If you deploy after `<CUTOFF>`: change it to the next Warsaw midnight in UTC
(22:00 in summer time, 23:00 from 25.10) in 02 (2 places) and 03 (2 places).

## Checks
```sql
-- refresh status (exception = error)
SELECT view, status, last_success_time, next_refresh_time, exception
FROM system.view_refreshes WHERE database = 'bi_sandbox';

-- backfill progress: rows per day
SELECT action_date, sum(actions_cnt) actions, count() rows
FROM bi_sandbox.bi_antebet_rounds GROUP BY action_date ORDER BY action_date;

-- report
SELECT report_date, sum(total_rounds), sum(total_bet_amount), sum(total_win)
FROM bi_sandbox.bi_antebet_report_v GROUP BY report_date ORDER BY report_date DESC;
```
Repairing a bad backfill day D:
`DELETE FROM bi_sandbox.bi_antebet_rounds WHERE action_date <= 'D';` and the MV reloads it by itself
(if bi_antebet_report already has those days: also `DELETE FROM bi_sandbox.bi_antebet_report WHERE report_date >= 'D' - 1;`).

## Rollback (MVs first: they sit on the production insert path)
```sql
DROP VIEW IF EXISTS bi_sandbox.bi_antebet_rounds_mv;
DROP VIEW IF EXISTS bi_sandbox.bi_antebet_rounds_extra_mv;
DROP VIEW IF EXISTS bi_sandbox.bi_antebet_backfill_mv;
DROP VIEW IF EXISTS bi_sandbox.bi_antebet_mv;
DROP VIEW IF EXISTS bi_sandbox.bi_antebet_recent_mv;
DROP VIEW IF EXISTS bi_sandbox.bi_antebet_report_v;
-- DROP USER IF EXISTS bi_antebet_definer;   -- only after the MVs are dropped
-- then optionally the tables: bi_antebet_rounds, bi_antebet_report, bi_antebet_report_recent
```
