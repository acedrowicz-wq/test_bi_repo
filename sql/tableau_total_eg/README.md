# Total EG data source: from a CSV to ClickHouse (ProdCH)

Moves the Tableau data source `Total_EG_datasource` (exported as
`Total_EG_datasource_Migrated_Data.csv`) to a live connection on ClickHouse.
Tableau reads one view: **`bi_sandbox.bi_total_eg_v`**. Its column names, order and types
are the same as in the CSV.

## What the CSV is
- 8,441 rows × 122 columns. All rows are **live bets** (`Product name = Live`) of **`phoenix_roulette`**
  on **2026-10-09 (UTC)**, 61 casinos. So the export was filtered in the workbook (game + day).
- The old source was a combination of two published sources (`Table Names` =
  `localhost/CHTotalEGoverview2026/sqlproxy`, `Table Names-1` = `localhost/CHJoinedroundsandbets2026/sqlproxy`).
  The CSV has rows from the live-bets branch only, so 53 columns are empty in all rows
  (slot actions, sessions, client stats; 2 of them are Tableau calculations). The SQL returns the base ones
  as typed `NULL` with the same name (see below).
- Grain: **1 row = 1 bet** (`platform.bets.mongoId`).

## Things we found when checking the CSV against ProdCH (2026-10-09, phoenix_roulette)
| # | Finding | Effect after the switch |
|---|---|---|
| 1 | **1,137 bets appear twice** (identical rows): every bet of the 6 casinos of the partners `Infingame-Patrianna` (mcluck, hellomillions, playfame, scratchful) and `Infingame-Primetech` (chanced, punt). Cause: the old source joined `platform.mysql_partners` (raw PeerDB CDC, no dedup), where partners 13 and 14 have 2 versions each. | The new source has **no duplicates**: for that day the bet sum is EUR 49,977.92, not EUR 56,898.40 (**-12%** compared with the old dashboard for the whole day, **-50%** for those 6 casinos). This fixes a bug. It is not a regression. |
| 2 | The CSV has 7,304 unique bets. ProdCH has **7,351** (+47, +0.6%): the casino `spinobon.prod` (9 bets) is missing, plus 38 single bets spread over the day (whole rounds missing, e.g. round `6ac867a8c84b0bf59fc6bb8a`). These are not late inserts: all of them were in ClickHouse at most ~3 min after the bet. Most likely the old source used an older extract or an inner join to the rounds. | +0.6% bets for that day. Check this once against the backoffice (`04_validation.sql`). |
| 3 | `updatedAt_str` / `statusUpdatedAt_str` look like `2026-10-09 02:October:01`: Warsaw time, format `%Y-%m-%d %H:%M:%S`, and in ClickHouse `%M` means the **month name**, not the minutes. | Kept **1:1** so that filters / calculations that use these strings still work. Correct format: `'%Y-%m-%d %H:%i:%S'` (change it in the SQL once the dashboards no longer depend on it). |
| 4 | `incremental_id` = `toUnixTimestamp(createdAt)` (e.g. 1791505396 = 2026-10-09 00:23:16 UTC). Most likely used for an incremental extract refresh. | Same value. It can still be the incremental-refresh key of an extract. |
| 5 | `partner_name` = the partner whose `wls` list contains the casino. `acornfunna` and `yaycasinocomna` are in no list, so their partner is empty (in `whitelabels.mongoPartnerId` yaycasinocomna has Infingame-Blazesoft). | Same rule (empty). Using `mongoPartnerId` would fill more rows, but that would change the dashboard. |

**Validation:** for 101 bets of 8 casinos (incl. the partner-less, the renamed and the Patrianna/Primetech
ones), 41 columns (all 38 populated base columns + `autoplay`, `freeSpins`, `freespinTransactionMode`) were compared
value by value with the result of `01_recent_days.sql`: **0 differences** (`Country_name` uses the same
expression as `Country Name`). Hour totals and per-casino totals also match
(apart from #1 and #2).

## KROK 1: column mapping (CSV → ClickHouse)

Sources: `platform.bets` **FINAL** (`b`), dictionaries `platform.whitelabels_d` (`wl`),
`platform.currency_d` (`cur`), `platform.partners_d` (`partner`, via the `wls` list),
`bi_sandbox.country_names_d` (`country_names`, new, `00_country_names.sql`).
Legend: **CH** = from ClickHouse (checked 1:1) · **NULL** = empty in the whole CSV, typed `NULL` ·
**const** = a constant · **Tableau** = a Tableau calculation, NOT in the SQL.

| CSV column | Type | Kind | ClickHouse expression |
|---|---|---|---|
| `actionName` | Nullable(String) | NULL | slot branch (`slot_actions.actionName`) |
| `Agregated date` | Date | CH | `toStartOfMonth(b.createdAt)` |
| `Anchor Filter (last 6 month)` | | Tableau | depends on TODAY() / a parameter |
| `autoplay` | Nullable(String) | CH | `nullIf(b.autoplay, '')` |
| `Bet_day_date` | Date | CH | `toDate(b.createdAt)` (UTC day) |
| `browser`, `browser_cmd` | Nullable(String) | NULL | sessions / client branch |
| `Casino name` | String | CH | `replaceRegexpAll(wl.name, '\.prod$\|-pragmatic\|_v1\|vegangster1', '')` (reproduces all 61 CSV values) |
| `country` | String | CH | `b.country` (ISO-2) |
| `Country Code` | Nullable(String) | NULL | |
| `Country Name` | String | CH | `dictGetOrDefault('bi_sandbox.country_names_d','name', b.country, b.country)` |
| `Country_name` | String | CH | as `Country Name` |
| `Created datetime` | Nullable(DateTime) | NULL | |
| `Created hour` | DateTime('UTC') | CH | `toDateTime(toStartOfHour(b.createdAt),'UTC')` |
| `createdAt-1..3` | Nullable(DateTime) | NULL | |
| `currency` | String | CH | `b.currency` |
| `Day of Month of Date` | | Tableau | DAY() of a date field |
| `dealer_name`, `device`, `device_cmd`, `dpi_cmd` | Nullable(String) | NULL | |
| `freeSpins` | Nullable(String) | CH | `b.freeSpins` without the `\0` padding of FixedString |
| `freespinTransactionMode` | Nullable(String) | CH | `b.freespinTransactionMode` |
| `Game name` | String | CH | `replaceAll(b.gameId, '_', ' ')` ("phoenix roulette"; not `games.name` = "Phoenix Roulette x2000") |
| `gameFamily`, `GameName` | Nullable(String) | NULL | |
| `gameId` | String | CH | `b.gameId` |
| `Games Family` | | Tableau | a group ("Other"); `games.gameFamilyId` = "Autoroulettes", so it does not come from CH |
| `iframeResolution_cmd`, `ip` | Nullable(String) | NULL | |
| `Is current period?`, `Is previous period?` | | Tableau | depend on TODAY() / parameters |
| `KAM agregation` | | Tableau | a group over `Casino name` (identical values in the CSV) |
| `label` | String | CH | `wl.label` |
| `Last month`, `Not today`, `Previous month` | | Tableau | depend on TODAY() |
| `mongoId` | String | CH | `toString(b.mongoId)` (bet id) |
| `mongoId-2` | String | CH | `toString(b.playerMongoId)` (`players.mongoId`, no JOIN needed) |
| `mongoId-3`, `name`, `os`, `os_cmd` | Nullable(String) | NULL | |
| `partner_name` | Nullable(String) | CH | partner whose `partners_d.wls` contains `b.wlId` |
| `platform_cmd` | Nullable(String) | NULL | |
| `playerMongoId` | String | CH | `toString(b.playerMongoId)` |
| `playerMongoId-1` | Nullable(String) | NULL | |
| `Product name` | String | const | `'Live'` |
| `real_country`, `Regions` | String | CH | as `Country Name` |
| `result` | Nullable(String) | NULL | |
| `roundMongoId` | String | CH | `toString(b.roundMongoId)` |
| `Scaf date` | Date | CH | `toDate(b.createdAt)` |
| `screenResolution_cmd`, `Session mongo id`, `Session status`, `sex` | Nullable(String) | NULL | |
| `status` | String | CH | `b.status` (filter: `COMPLETED`) |
| `status-2` | Nullable(String) | NULL | |
| `statusUpdatedAt_str` | String | CH | `formatDateTime(b.statusUpdatedAt,'%Y-%m-%d %H:%M:%S','Europe/Warsaw')` (finding #3) |
| `symbol` | String | CH | `b.currency` (= `currency.symbol`) |
| `Table Names`, `Table Names-1` | String | const | the old union labels |
| `timeToPlay_cmd`, `title` | Nullable(String) | NULL | |
| `Title` | String | CH | `cur.title` ("Sweepstake Coin custom code") |
| `tokenMongoId` | String | CH | `toString(b.tokenMongoId)` |
| `Type` | String | CH | `cur.type` (regular / virtual) |
| `type`, `updatedAt-1` | NULL | NULL | |
| `updatedAt_str` | String | CH | `formatDateTime(b.updatedAt, …)` as above |
| `wl label` | Nullable(String) | NULL | |
| `wl name` | String | CH | `wl.name` |
| `wlId`, `wlUserId` | String | CH | `b.wlId`, `b.wlUserId` |
| `wlUserId-2` | Nullable(String) | NULL | |
| `1` | | Tableau | a record-count calculation |
| `all_rounds` | Nullable(Float64) | NULL | |
| `AvBet`, `AvRnds`, `Bets ` | | Tableau | formatted aggregates (`AvBet` = bet € to 1 decimal, `Bets ` = bet € to 0 decimals) |
| `betSize` | Decimal(30,12) | CH | `b.betSize` (player currency) |
| `Choose measure`, `Choose measure 2` | | Tableau | parameter-driven measures |
| `current quarter Filter`, `Days in a Quarter` | | Tableau | depend on TODAY() |
| `GGR`, `GGR per player` | | Tableau | `SUM(bet €) - SUM(win €)`, formatted |
| `id` | Nullable(String) | NULL | |
| `incremental_id` | UInt32 | CH | `toUnixTimestamp(b.createdAt)` (finding #4) |
| `is_time_empty` | Nullable(UInt8) | NULL | |
| `isFun` | UInt8 | CH | `cur.isFun` (filter: 0) |
| `muted_button_clicks`, `muted_rounds`, `playerId`, `playerId-1`, `playerId-2` | NULL | NULL | |
| `Players`, `Unique users`, `Rounds`, `Rounds live`, `RTP` | | Tableau | COUNTD / ratios, formatted |
| all `… (parameter control)` | | Tableau | parameters |
| `round_id`, `roundId`, `spin mongoId`, `Spins rounds` | NULL | NULL | |
| `Sum of bet €` | Decimal(16,4) | CH | `b.convertedBet` (EUR) |
| `Sum of win €` | Decimal(16,4) | CH | `b.convertedWin` (EUR) |
| `timeToEndJoin_in_seconds` | Nullable(Float64) | NULL | |
| `wl is test` | UInt8 | CH | `wl.isTest` (filter: 0) |
| `wl is test ` (trailing space) | Nullable(UInt8) | NULL | |
| `won` | Decimal(30,12) | CH | `b.won` (player currency) |

Extra columns not in the CSV (`createdAt`, `updatedAt`, `statusUpdatedAt`, `convertedBet`, `convertedWin`,
`roundNumId`, `tenantId`): Tableau does not export **hidden** fields, so calculations of the
workbook may use base fields we cannot see. Returning them costs nothing and prevents red fields.

### Formats for Tableau
- Dates: native `Date` / `DateTime('UTC')` instead of the CSV strings (`10/9/2026`, `10/9/2026 12:00:00 AM`
  are just the Tableau display format). After the switch Tableau sees a date (not a string), so
  `DATEPARSE` / `DATE()` on these fields are no longer needed (they still work on a date).
- Money: `Decimal` (Tableau already reads `Decimal(38,4)` from `bi_antebet_report_v` without problems).
- `*_str` columns stay strings on purpose (finding #3).

### Fields left to Tableau
Everything marked **Tableau** above stays a workbook calculation. They depend on TODAY(), parameters
or aggregation, so they cannot be static columns. The SQL does not return them, so after
*Replace Data Source* their names do not clash. If a field turns red after the switch,
it was a base field of the old source: add it to the SQL (in the view) with the same name.

## KROK 2: operational query, last 3 days
`01_recent_days.sql`: a self-contained `SELECT` on `platform.bets FINAL` with
`createdAt >= toStartOfDay(now('UTC')) - INTERVAL 3 DAY`.
`createdAt` bounds both the partition (`toStartOfMonth(createdAt)`) and the first sorting-key column
(`toStartOfHour(createdAt)`). Measured on ProdCH: 211,514 bets, 0.18 s, 0 duplicates.
Filters: `status = 'COMPLETED'`, no test casinos, no fun currencies (= the CSV).

## KROK 3: full history, architecture
**Recommendation: one flat bet-level table in ClickHouse, loaded by refreshable MVs, and a view for Tableau.**
Neither a big `SELECT` on `platform.bets` for Tableau, nor a pre-aggregated table:

- One big Custom SQL in Tableau on `platform.bets` would run `FINAL` + dictionaries + JOIN on
  36 M rows for **every** dashboard query. ReplacingMergeTree needs `FINAL` or there are duplicates.
- A pre-aggregated table (e.g. per day × casino × game) would break the workbook: it computes
  `COUNTD` of players / rounds / sessions and per-bet averages, which need the bet grain.
- The bet grain is small for ClickHouse: ~36 M rows since 2022-12 (~75 k/day). One month loads in 0.6 s.

| What | Object | How often |
|---|---|---|
| history from 2022-12-01 + closed days (<= today-2 UTC) | `bi_total_eg_bets_mv` -> `bi_total_eg_bets` | every 5 min; 92 days per run (whole history in ~80 min), then +1 day after UTC midnight |
| open days (today-1, today) | `bi_total_eg_bets_recent_mv` -> `bi_total_eg_bets_recent` | every 15 min, atomic full replace |
| Tableau | `bi_total_eg_v` = closed + open days, CSV column names | live |

- Refreshable MVs, not an incremental MV: `platform.bets` gets a new row version on every status
  change (PeerDB), and an incremental MV would sit on the production insert path.
- The view reads plain MergeTree tables: no `FINAL`, no JOIN, no dictGet. Tableau filters on
  `Bet_day_date` use the `(bet_date, wl_id, game_id, mongo_id)` key and the monthly partitions.
- `recent` is cut at `max(bet_date)` of the history, so a day is never counted twice while the two MVs run.
- Everything runs as `bi_total_eg_definer` (HOST NONE), like Antebet.

Files, in deployment order: `00_country_names.sql`, `02_history_tables.sql` (user, grants, tables),
`03_history_mvs_and_view.sql` (MVs + view). `01_recent_days.sql` is a standalone query (needs only 00).
`04_validation.sql` = checks.

### Tableau
1. Data source → ClickHouse JDBC (same as Antebet: `hyxzs78gz1.europe-west4.gcp.clickhouse.cloud:8443`,
   the Tableau user already has SELECT on `bi_sandbox`), table **`bi_sandbox.bi_total_eg_v`**, Live.
2. In the workbook: *Data → Replace Data Source* (old → new). Fields are matched by name, so the
   calculations keep working.
3. Check: red fields (see "Fields left to Tableau"), then compare one day with `04_validation.sql`
   (keep findings #1 and #2 in mind).

### Operations
```sql
-- refresh status (exception = error)
SELECT view, status, last_success_time, next_refresh_time, exception
FROM system.view_refreshes WHERE database = 'bi_sandbox' AND view LIKE 'bi_total_eg%';

-- backfill progress
SELECT min(bet_date), max(bet_date), count() FROM bi_sandbox.bi_total_eg_bets;
```
- **Stall:** the history MV moves on from `max(bet_date)`. A 92-day window with no bets at all
  would stop it. This cannot happen from 2022-12-15 on (bets every day).
- **Repairing day D** (e.g. a bet changed status after D+2):
  `ALTER TABLE bi_sandbox.bi_total_eg_bets DELETE WHERE bet_date = 'D';`, then the `SELECT` of
  `bi_total_eg_bets_mv` with `date_from = date_to = 'D'` as `INSERT INTO bi_sandbox.bi_total_eg_bets`.
- **Changing logic / a new column:** `DROP VIEW` both MVs, `TRUNCATE` both tables, change the DDL,
  create the MVs again. The history reloads itself in ~80 min.
- **Rollback:** `DROP VIEW bi_sandbox.bi_total_eg_bets_mv; DROP VIEW bi_sandbox.bi_total_eg_bets_recent_mv;
  DROP VIEW bi_sandbox.bi_total_eg_v;`, then optionally the tables, the dictionary and `DROP USER bi_total_eg_definer`.

### Still open
- The other branches of the old source (slot actions, sessions / client stats: `actionName`,
  `device`, `os`, `*_cmd`, `Session …`, `muted_*`, `timeToEndJoin_in_seconds`, ...) are not in the
  CSV, so they are `NULL` for now. To fill them we need the definition of `CHTotalEGoverview2026`
  (its Custom SQL or the `.tds`), or a CSV export that has slot / session rows.
