# Total EG data source: from a CSV to ClickHouse (ProdCH), hourly, Live + Slots

Moves the Tableau data source `Total_EG_datasource` (exported as
`Total_EG_datasource_Migrated_Data.csv`) to a live connection on ClickHouse.
Tableau reads one view: **`bi_sandbox.bi_total_eg_v`**, with the CSV's column names.

## Grain: hourly, no single bets
1 row = **hour (UTC) × product (Live / Slots) × casino × game × currency × country × player × session
(`tokenMongoId`) × status × free-spin context**, plus the **live round** (`roundMongoId`) for Live and the
**action** (`actionName`) for Slots.

| CSV column | Meaning in the hourly source | In Tableau |
|---|---|---|
| `mongoId` | **number of unique bets** in the row (Live: bets; Slots: actions with a stake) | `SUM([mongoId])` (was `COUNTD([mongoId])` on the bet-level CSV) |
| `spin mongoId` | **number of unique slot actions** in the row (all actions, incl. the bonus starts `bonus_init` / `hyperspin_init`); NULL for Live | `SUM([spin mongoId])`; the workbook's `Spins rounds` = `SUM(CASE [actionName] WHEN 'spin' / 'buy_spin' / 'bonus_init' / 'hyperspin_init' THEN [spin mongoId] END)` (2026-10-09: 21,363,898) |
| `slot_rounds` | slot rounds started (counted on the starting action, adds up exactly; = backoffice); NULL for Live. Not named `Spins rounds`: that is a workbook calculation | `SUM([slot_rounds])` |
| `roundMongoId` | the live round (a live round is shared by many players, so it has to stay in the grain); NULL for Slots | `COUNTD([roundMongoId])` = live rounds, exact |
| `wlUserId`, `playerMongoId`, `mongoId-2` | player | `COUNTD` exact (the player is in the grain) |
| `tokenMongoId` | session | `COUNTD` exact |
| `betSize`, `won` | sums in player currency (currency is in the grain) | `SUM` |
| `Sum of bet €`, `Sum of win €` | sums in EUR | `SUM` |
| `Created hour` | the hour (`DateTime`, UTC) | |
| `incremental_id` | unix time of the hour | incremental-extract key (closed days only) |
| `updatedAt_str`, `statusUpdatedAt_str` | the latest timestamp of the row, old format (see finding #3) | |

Size (ProdCH, 2026-10-09):

| | facts | hourly rows | history |
|---|---|---|---|
| Live | 62.5 k bets, 15.6 k rounds | ~62 k / day (≈ the bets: 1 player × 1 round ≈ 1 bet) | ~36 M rows since 2022-12 |
| Slots | 22.3 M actions, 21.2 M rounds | ~0.5 M / day (**45× fewer**) | ~0.35 bn rows since 2024-10 |

Without `actionName` the slot rows would drop to ~0.28 M / day, and without the session to
~0.23 M / day. That is one line in `parts`/`03` if the dashboards do not need it.

## What the CSV is, and what we found
- 8,441 rows, all **live** bets of `phoenix_roulette` on **2026-10-09 (UTC)**, 61 casinos: a filtered
  export from the workbook. It has **no slot rows**, so the slot branch is built from `platform.slot_actions`
  with the canonical rules and checked against the backoffice (`agg_daily`, see Validation).
- The old source combined two published sources (`Table Names` = `…/CHTotalEGoverview2026/sqlproxy`,
  `Table Names-1` = `…/CHJoinedroundsandbets2026/sqlproxy`). 53 columns are empty in the CSV (client
  stats, sessions, ...); the SQL returns the base ones as typed `NULL` with the same name.

| # | Finding | Effect after the switch |
|---|---|---|
| 1 | **1,137 bets appear twice** in the CSV: all bets of the 6 casinos of `Infingame-Patrianna` (mcluck, hellomillions, playfame, scratchful) and `Infingame-Primetech` (chanced, punt). Cause: the old source joined `platform.mysql_partners` (raw PeerDB CDC, no dedup), where partners 13 and 14 have 2 versions. | **No duplicates** now: for that day/game the live bet sum is EUR 49,977.92, not EUR 56,898.40 (**-12%**, **-50%** for those 6 casinos). A bug fix, not a regression. |
| 2 | The CSV has 7,304 unique bets, ProdCH **7,351** (+0.6%): casino `spinobon.prod` (9 bets) missing, plus 38 single bets (whole rounds missing). Not late inserts (all in ClickHouse ≤ 3 min after the bet). | +0.6% live bets for that day. |
| 3 | `updatedAt_str` / `statusUpdatedAt_str` = `2026-10-09 02:October:01`: Warsaw time, `%Y-%m-%d %H:%M:%S`, and in ClickHouse `%M` is the **month name**. | Kept 1:1. Correct format: `'%Y-%m-%d %H:%i:%S'`. |
| 4 | `incremental_id` = `toUnixTimestamp(createdAt)`. | Now the unix time of the hour. |
| 5 | `partner_name` = the partner whose `wls` list contains the casino; `acornfunna`, `yaycasinocomna` are in no list → empty. | Same rule. |
| 6 | Live status: the CSV has only `COMPLETED`. | Live = `COMPLETED` + `FINALIZED` + `INTERNAL_TRANSACTION` (live free spins, from 2025-12-05; ~1,000 bets/day), like the backoffice. `status` is a column, so a dashboard can still filter `COMPLETED`. Without them live was 1.6% below `agg_daily` (2026-10-08); with them 62,211 vs 62,221 (the rest = settlement day). Slots = `COMPLETED`, `FINALIZED`, `INTERNAL_TRANSACTION` (final-only free-spin wins). |

## Validation (ProdCH)
- **Live vs CSV:** the 101 bets of 8 casinos (incl. partner-less, renamed, Patrianna/Primetech), aggregated to the
  hourly grain on both sides: **identical** (101 rows, same MD5 of hour, casino, player, session, round,
  currency, country, number of bets, bet €, win €). Earlier, 41 columns were compared value by value at bet level: 0 differences.
- **Slots vs backoffice** (`agg_daily`, 2026-10-09, source = slot): bets 21,243,902 vs 21,243,870,
  bet EUR 18,347,296.29 vs 18,347,296.13. Rounds: the sum of the hourly `Spins rounds` = the exact
  distinct count of the day (21,243,902), so they add up without double counting.
- `01_recent_days.sql` (all 91 columns) runs on ProdCH: last 3.4 days = 1.64 M slot rows + 0.21 M live rows in 14 s.

## KROK 1: column mapping (CSV → ClickHouse)
Sources: `platform.bets` FINAL (Live), `platform.slot_actions` FINAL (Slots), dictionaries
`platform.whitelabels_d`, `platform.currency_d`, `platform.partners_d` (via `wls`), and
country names inlined with `transform()` in the alias layer (ISO 3166-1, see `gen/parts.py`). The full expression of every column is in
`01_recent_days.sql` (alias layer at the top, the same as in the view).

| Kind | CSV columns |
|---|---|
| **From ClickHouse** (dimensions) | `Agregated date` (month), `Bet_day_date`, `Scaf date` (UTC day), `Created hour`, `Casino name` (`wl.name` without `.prod`, `-pragmatic`, `_v1`, `vegangster1`, reproduces all 61 CSV values), `wl name`, `label`, `wlId`, `wl is test`, `partner_name`, `wlUserId`, `playerMongoId`, `mongoId-2`, `tokenMongoId`, `roundMongoId` (live), `actionName` (slots), `gameId`, `Game name` (`gameId` with spaces), `country`, `Country Name` / `Country_name` / `real_country` / `Regions` (ISO name via `transform()`), `currency`, `symbol`, `Title`, `Type`, `isFun`, `status`, `autoplay` (live), `freeSpins`, `freespinTransactionMode`, `Product name` (Live / Slots), `updatedAt_str`, `statusUpdatedAt_str`, `incremental_id`, `Table Names`, `Table Names-1` (constants) |
| **From ClickHouse** (measures) | `mongoId` (number of bets), `Spins rounds`, `betSize`, `won`, `Sum of bet €`, `Sum of win €` |
| **Typed NULL** (empty in the CSV, no source in ClickHouse) | `browser`, `browser_cmd`, `Country Code`, `Created datetime`, `createdAt-1..3`, `dealer_name`, `device`, `device_cmd`, `dpi_cmd`, `gameFamily`, `GameName`, `iframeResolution_cmd`, `ip`, `mongoId-3`, `name`, `os`, `os_cmd`, `platform_cmd`, `playerMongoId-1`, `result`, `screenResolution_cmd`, `Session mongo id`, `Session status`, `sex`, `status-2`, `timeToPlay_cmd`, `title`, `type`, `updatedAt-1`, `wl label`, `wlUserId-2`, `all_rounds`, `id`, `is_time_empty`, `muted_button_clicks`, `muted_rounds`, `playerId`, `playerId-1`, `playerId-2`, `round_id`, `roundId`, `spin mongoId`, `timeToEndJoin_in_seconds`, `wl is test ` (trailing space) |
| **Tableau calculations** (not in the SQL) | `Anchor Filter (last 6 month)`, `Is current period?`, `Is previous period?`, `Last month`, `Not today`, `Previous month`, `current quarter Filter`, `Days in a Quarter`, `Day of Month of Date`, `Choose measure`, `Choose measure 2`, every `… (parameter control)`, `AvBet`, `AvRnds`, `Bets `, `GGR`, `GGR per player`, `Players`, `Unique users`, `Rounds`, `Rounds live`, `RTP`, `1`, `Games Family` (a group: "Other"), `KAM agregation` (a group over `Casino name`) |

Formats: native `Date` / `DateTime('UTC')` instead of the CSV strings (`10/9/2026` is only Tableau's
display format), money as `Decimal(38,4)` / `Decimal(38,12)` (Tableau already reads `Decimal(38,4)` from
`bi_antebet_report_v`), `*_str` stay strings on purpose (finding #3).

### What has to change in the workbook
- Every calculation that counts bets with `COUNTD([mongoId])` / `COUNT([mongoId])` → **`SUM([mongoId])`** (`COUNT` now counts rows, not bets).
- `[spin mongoId 1]` (the old source's field) → *Replace References* with **`[spin mongoId]`**; the formulas stay as they are.
- Slot rounds: the workbook's `Spins rounds` calculation on `[spin mongoId]`, or `SUM([slot_rounds])` for rounds started only. Live rounds stay `COUNTD([roundMongoId])`.
- Averages "per bet" (e.g. `AvBet`) = `SUM([Sum of bet €]) / SUM([mongoId])`, not `AVG(...)`.
- Players / sessions (`COUNTD([wlUserId])`, `COUNTD([tokenMongoId])`) do not change.
- If a field turns red after *Replace Data Source*, it was a base field of the old source: add it to the
  alias layer with the same name.

## KROK 2: operational query, last 3 days
`01_recent_days.sql`: a self-contained query (needs no objects) on `platform.bets FINAL` +
`platform.slot_actions FINAL`, window `createdAt >= toStartOfDay(now('UTC')) - INTERVAL 3 DAY`.
`createdAt` bounds the partition (`toStartOfMonth(createdAt)`) and the first sorting-key column
(`toStartOfHour(createdAt)`) of both tables. ~4 s per day of slots, live is negligible.

## KROK 3: full history, architecture
**One hourly table in ClickHouse, loaded by refreshable MVs, and a view for Tableau.**
- One big Custom SQL in Tableau would aggregate `slot_actions` (6.8 bn rows, 829 GiB) with `FINAL` on every
  dashboard query. That is not feasible.
- Aggregating higher than player × session (e.g. day × casino × game) would break `COUNTD` of players and
  sessions, which the workbook uses.
- The hourly player grain is 45× smaller than the slot facts, and the dashboard queries read a plain
  MergeTree table (no `FINAL`, no JOIN, no dictGet).

| What | Object | How often |
|---|---|---|
| Live history from 2022-12-19 + closed days (<= today-2 UTC) | `bi_total_eg_live_mv` → `bi_total_eg_hourly` | every 5 min, 92 days per run (~15 runs) |
| Slot history from 2024-10-29 + closed days | `bi_total_eg_slots_mv` → `bi_total_eg_hourly` | every 1 min, 3 days per run (~240 runs ≈ 4 h, ~12 s each) |
| open days (today-1, today), both | `bi_total_eg_recent_mv` → `bi_total_eg_hourly_recent` | every 15 min, atomic full replace |
| Tableau | `bi_total_eg_v` | live |

- Refreshable, not incremental, MVs: both fact tables are ReplacingMergeTree tables fed by PeerDB; every status
  change is a new row version. An incremental MV would aggregate every version, and it would sit on the
  production insert path.
- Each history MV continues from `max(bet_date)` of its product. First real-money days (from `agg_daily`):
  live 2022-12-19, slots 2024-10-29. Slots have no gaps, live has one 1-day gap (2023-01-22), so no window is
  ever empty and the MVs cannot stall.
- `recent` is cut per product at `max(bet_date)` of the history, so no day is counted twice.
- Everything runs as `bi_total_eg_definer` (HOST NONE), like Antebet.

Scripts meant to be run in the ProdCH SQL console (`deploy_all.sql`, `07_…`) contain no comments inside the SQL: the console splits a script into statements without understanding comments, and an apostrophe or `;` in a comment cuts a statement in half.

Files, in deployment order: `00_cleanup.sql`, `02_history_tables.sql` (user, grants, tables),
`03_history_mvs_and_view.sql` (MVs + view). `01_recent_days.sql` = the standalone query, `04_validation.sql` = checks. `05_fix_live_internal_transaction.sql`, `06_fix_view_int_types.sql`, `07_add_spin_mongoid.sql` = one-off changes of 2026-10-10 for a deployment made before them (`deploy_all.sql` already contains them; 07 contains 06).
`01` and `03` are generated from one place, `gen/parts.py` (the live / slot aggregations and the alias layer):
change a column there and run `cd gen && python3 gen.py ..`.

### Tableau
1. Data source → ClickHouse JDBC (`hyxzs78gz1.europe-west4.gcp.clickhouse.cloud:8443`, the Tableau user
   already has SELECT on `bi_sandbox`), table **`bi_sandbox.bi_total_eg_v`**, Live (or an extract with an
   incremental refresh on `incremental_id`; only closed days are immutable, so refresh the last 2 days fully).
2. *Data → Replace Data Source* (old → new), then the changes in "What has to change in the workbook".
3. Compare one day with `04_validation.sql` (keep findings #1, #2 and #6 in mind).

### Operations
```sql
SELECT view, status, last_success_time, next_refresh_time, exception
FROM system.view_refreshes WHERE database = 'bi_sandbox' AND view LIKE 'bi_total_eg%';

SELECT product, min(bet_date), max(bet_date), count(), sum(bets)
FROM bi_sandbox.bi_total_eg_hourly GROUP BY product;
```
- **Repairing day D of a product P:** `ALTER TABLE bi_sandbox.bi_total_eg_hourly DELETE WHERE product = 'P' AND bet_date = 'D';`,
  then the `SELECT` of the product's history MV with `date_from = date_to = 'D'` as an `INSERT INTO bi_sandbox.bi_total_eg_hourly`.
- **Changing logic / a column:** `DROP VIEW` the 3 MVs, `TRUNCATE` both tables, change the DDL, create the MVs again
  (the history reloads itself in ~4 h).
- **Rollback:** `DROP VIEW` `bi_total_eg_live_mv`, `bi_total_eg_slots_mv`, `bi_total_eg_recent_mv`, `bi_total_eg_v`,
  then optionally the tables, the dictionary and `DROP USER bi_total_eg_definer`.
