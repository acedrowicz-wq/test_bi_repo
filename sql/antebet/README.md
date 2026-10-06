# Antebet report on ClickHouse (ProdCH, database `bi_sandbox`)

Migration of the Tableau Antebet report (Custom SQL on `slot_actions` + `mysql_slot_actions_extra`)
to objects in ClickHouse that refresh themselves. Tableau reads one view: `bi_sandbox.bi_antebet_report_v`.

## Report day = UTC
`report_date` = **UTC** day of the round's first action (`toDate(min(first_action_at), 'UTC')`),
the same as the backoffice (`platform.agg_daily`). The original Tableau script used the Warsaw day,
which differed from the backoffice by -2% to +10% per game (a 2 h window shift).
Switched to UTC on 2026-10-06.

Expected differences from the backoffice "Games Report / GGR (without Promo)":
- bets ~0.01%: the backoffice converts at the daily currency rate, we use `convertedBet` (rate at bet time),
- wins ~0.1%: the backoffice assigns a win to its settlement day, we assign it to the round start day
  (freespin wins of a round started before midnight go to the previous day),
- promo (free spins) is **included** in the report, like in the original script (a few EUR per game per day).

## Bonus type: `bonus_feature` column
| Value | When |
|---|---|
| `Buy mode N` | the round has a `buy_spin`; N = `finalContext.last_args.selected_mode` of that action (each mode has a different price, e.g. thor_hit_the_bonus: 1 = 50x, 2 = 150x, 3 = 400x base bet) |
| `Ante >= 50` | no `buy_spin`, but `ante_bet >= 50` (in `spin_category` = `3. Buy Bonus`) |
| `Triggered bonus` | a bonus triggered by a regular spin: the round has completed actions other than `spin` (respin / freespin / bonus_spins_stop ...) |
| `No bonus` | everything else |

Mode numbers are the game's raw values; a mapping to names (e.g. "Super Bonus") can be added as a dictionary / CASE.

## Architecture (everything runs by itself)

| What | Object | How often |
|---|---|---|
| new rounds (amounts, dimensions) | `bi_antebet_rounds_mv`: `platform.slot_actions` -> `bi_antebet_rounds` | on every insert |
| `ante_bet` / `bonus_type` | `bi_antebet_rounds_extra_mv`: `platform.mysql_slot_actions_extra` -> `bi_antebet_rounds` | on every insert |
| round history before CUTOFF | `bi_antebet_backfill_mv` -> `bi_antebet_rounds` | 1 day/min; done, every run is now a no-op |
| closed days (<= today-2 UTC) | `bi_antebet_mv` -> `bi_antebet_report` | every 5 min (3 days per run when catching up, then +1 day after UTC midnight) |
| open days | `bi_antebet_recent_mv` -> `bi_antebet_report_recent` | every 15 min (atomic table swap) |
| Tableau | `bi_antebet_report_v` = report + recent | — |

All MVs run as the technical user `bi_antebet_definer` (HOST NONE, no login), not as
the console user: the incremental MVs sit on the production insert path of `platform.slot_actions` (PeerDB).

Files, in deployment order: `00_definer_user.sql`, `01_tables.sql`, `02_incremental_mvs.sql`,
`03_backfill_mv.sql`, `04_report_mvs_and_view.sql` (`deploy_all.sql` = 01-04 without comments).
CUTOFF of the deployment: `2026-10-06 12:50:00` UTC (02 and 03, 2 places each).

## Deployment history
| When (UTC) | What |
|---|---|
| 2026-10-05 15:06 | objects created in `bi_sandbox` (moved from `adam_sandbox`, which was dropped) |
| 2026-10-05 15:19 | CUTOFF moved to 16:00 UTC, backfill without waiting for midnight |
| 2026-10-05 ~17:00 | round history 20.08-05.10 loaded; verified: 03.10 matches the original script 1:1 |
| 2026-10-06 09:21 | report switched to the UTC day (`bi_antebet_mv`, `bi_antebet_recent_mv` recreated, report tables truncated) |
| 2026-10-06 ~13:00 | `bonus_feature` column added (bonus type: Buy mode N / Triggered bonus / Ante >= 50 / No bonus); full rebuild, CUTOFF 12:50 UTC |

## Changing report logic (without reloading rounds)
Only the report layer is recomputed from `bi_antebet_rounds`:
```sql
DROP VIEW IF EXISTS bi_sandbox.bi_antebet_mv;
DROP VIEW IF EXISTS bi_sandbox.bi_antebet_recent_mv;
TRUNCATE TABLE bi_sandbox.bi_antebet_report;
TRUNCATE TABLE bi_sandbox.bi_antebet_report_recent;
-- then both CREATE MATERIALIZED VIEW statements from 04_report_mvs_and_view.sql
```
The history is rebuilt by itself in ~80 min (16 runs x 5 min). Changes needing new columns in
`bi_antebet_rounds` (e.g. a promo flag) also require reloading the rounds (backfill).

## Checks
```sql
-- refresh status (exception = error)
SELECT view, status, last_success_time, next_refresh_time, exception
FROM system.view_refreshes WHERE database = 'bi_sandbox';

-- rounds per day (action_date = Warsaw day of the action)
SELECT action_date, sum(actions_cnt) actions, count() rows
FROM bi_sandbox.bi_antebet_rounds GROUP BY action_date ORDER BY action_date;

-- report (report_date = UTC)
SELECT report_date, sum(total_rounds), sum(total_bet_amount), sum(total_win)
FROM bi_sandbox.bi_antebet_report_v GROUP BY report_date ORDER BY report_date DESC;
```
Repairing a bad round day D: `DELETE FROM bi_sandbox.bi_antebet_rounds WHERE action_date <= 'D';`
(the backfill MV reloads it by itself), then rebuild the report as in "Changing report logic".

## Tableau
Connection: ClickHouse JDBC, `hyxzs78gz1.europe-west4.gcp.clickhouse.cloud:8443`, user `mysql4hyxzs78gz1`
(`default_role`, already has SELECT on `bi_sandbox`). Data source: `bi_sandbox.bi_antebet_report_v`, Live.
RTP as a calculated field: `SUM([total_win]) / SUM([total_bet_amount])` (not AVG of the `RTP` column).

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
