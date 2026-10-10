import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parts import live, slots, ALIASES
out = sys.argv[1]

def ind(s, n=4):
    return "\n".join((" " * n + l) if l else l for l in s.splitlines())

# ---------------- 01: operational query ----------------
w3 = "{a}.createdAt >= toStartOfDay(now('UTC')) - INTERVAL 3 DAY                   -- the window: last 3 days (UTC)"
q01 = f"""-- Step 2. Operational query: the LAST 3 DAYS (UTC), hourly grain, with the exact
-- column names of the CSV "Total_EG_datasource" (Tableau). Live + Slots.
--
-- Grain (1 row): hour (UTC) x product x casino x game x currency x country x player
--                x session (tokenMongoId) x status x free-spin context
--                + live: round (roundMongoId)   + slots: action (actionName).
-- There is no single-bet information: "mongoId" is the NUMBER OF UNIQUE BETS of the row
-- (a measure, SUM in Tableau), "Spins rounds" the number of slot rounds (SUM).
-- COUNTD of players ("wlUserId", "playerMongoId"), sessions ("tokenMongoId") and live
-- rounds ("roundMongoId") stay exact, because those ids are part of the grain.
-- Fields Tableau computes itself (period flags, parameters, formatted measures) stay in
-- the workbook - see README.md.
--
-- Self-contained: no objects needed (country names are inlined with transform()).
-- Performance: platform.bets and platform.slot_actions are PARTITION BY toStartOfMonth(createdAt),
-- ORDER BY (toStartOfHour(createdAt), wlUserId, mongoId): the createdAt bound prunes partitions
-- and granules. Measured on ProdCH: 1 day of slots (22 M actions -> 0.5 M rows) = ~4 s;
-- live is ~1% of that.

SELECT
{ALIASES}
FROM
(
{ind(live(w3))}

    UNION ALL

{ind(slots(w3))}
)
SETTINGS max_bytes_before_external_group_by = 8000000000;
"""
open(f"{out}/01_recent_days.sql", "w").write(q01)

# ---------------- 03: MVs + view ----------------
def hist_where(start, chunk):
    return ("{a}.createdAt >= toDateTime64(date_from, 6, 'UTC')\n"
            "  AND {a}.createdAt <  toDateTime64(date_to + 1, 6, 'UTC')\n"
            "  AND date_to >= date_from                                                     -- nothing to do = nothing is read")

def hist_mv(name, product, start, chunk, every, body_fn, note):
    return f"""-- ---------------------------------------------------------------------
-- {note}
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.{name}
REFRESH EVERY {every}
APPEND TO bi_sandbox.bi_total_eg_hourly
DEFINER = bi_total_eg_definer SQL SECURITY DEFINER
AS
WITH
    toDate('{start}')                                                           AS start_day,
    toDate(now(), 'UTC')                                                         AS today,
    greatest((SELECT maxIf(bet_date, product = '{product}') FROM bi_sandbox.bi_total_eg_hourly) + 1, start_day) AS date_from,
    least(date_from + {chunk - 1}, today - 2)                                             AS date_to      -- date_to < date_from = nothing to do
{body_fn(hist_where(start, chunk))}
SETTINGS max_bytes_before_external_group_by = 8000000000;
"""

wr = "{a}.createdAt >= toDateTime64(if({a_is_live}, date_from_live, date_from_slots), 6, 'UTC')"
def recent_where(is_live):
    return "{a}.createdAt >= toDateTime64(" + ("date_from_live" if is_live else "date_from_slots") + ", 6, 'UTC')"

q03 = f"""-- Step 3b. Loading (refreshable MVs) and the view Tableau connects to.
-- Requires 00_cleanup.sql and 02_history_tables.sql.
--
-- Why refreshable MVs and not incremental MVs on the fact tables:
--   * platform.bets / platform.slot_actions are ReplacingMergeTree tables fed by PeerDB:
--     every status change inserts a new version of the row, so an incremental MV would
--     aggregate every version (double counting) and would sit on the production insert path
--     (an MV error = stalled replication).
--   * a refreshable MV reads the facts with FINAL on its own schedule, decoupled from inserts.
--
-- | What                                   | Object                        | How often                                      |
-- |----------------------------------------|-------------------------------|------------------------------------------------|
-- | Live history + closed days (<= today-2)| bi_total_eg_live_mv           | every 5 min, 92 days per run (~15 runs)        |
-- | Slot history + closed days (<= today-2)| bi_total_eg_slots_mv          | every 1 min, 3 days per run (~240 runs = ~4 h) |
-- |   both -> bi_total_eg_hourly (APPEND)  |                               | then +1 day per product after UTC midnight     |
-- | open days (today-1, today), both       | bi_total_eg_recent_mv         | every 15 min, atomic full replace              |
-- |   -> bi_total_eg_hourly_recent         |                               |                                                |
-- | Tableau                                | bi_total_eg_v (view)          | live                                           |
--
-- First day with real-money activity (agg_daily, non-test, non-fun): live 2022-12-19,
-- slots 2024-10-29, no gaps in slots and one 1-day gap in live (2023-01-22): no chunk is
-- ever empty, so the "continue from max(bet_date)" logic cannot stall.

{hist_mv('bi_total_eg_live_mv', 'Live', '2022-12-19', 92, '5 MINUTE', live,
         "1a. Live history + closed days -> bi_total_eg_hourly. One run = ~92 days (~5.8 M bets).")}
{hist_mv('bi_total_eg_slots_mv', 'Slots', '2024-10-29', 3, '1 MINUTE', slots,
         "1b. Slot history + closed days -> bi_total_eg_hourly. One run = 3 days (~66 M actions, ~12 s).")}
-- ---------------------------------------------------------------------
-- 2. Open days, both products -> bi_total_eg_hourly_recent (full replace, atomic swap).
--    Per product: everything after its last closed day (at most the last 3 days).
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_total_eg_recent_mv
REFRESH EVERY 15 MINUTE
TO bi_sandbox.bi_total_eg_hourly_recent
DEFINER = bi_total_eg_definer SQL SECURITY DEFINER
AS
WITH
    toDate(now(), 'UTC')                                                         AS today,
    greatest((SELECT maxIf(bet_date, product = 'Live')  FROM bi_sandbox.bi_total_eg_hourly) + 1, today - 3) AS date_from_live,
    greatest((SELECT maxIf(bet_date, product = 'Slots') FROM bi_sandbox.bi_total_eg_hourly) + 1, today - 3) AS date_from_slots
SELECT * FROM
(
{ind(live(recent_where(True)))}

    UNION ALL

{ind(slots(recent_where(False)))}
)
SETTINGS max_bytes_before_external_group_by = 8000000000;

-- ---------------------------------------------------------------------
-- 3. The view for Tableau: history + open days, with the CSV column names
--    (same alias layer as 01_recent_days.sql). `recent` is cut per product at
--    max(bet_date) of the history, so a day that was just appended is never
--    counted twice (the MVs run independently).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_sandbox.bi_total_eg_v
AS
WITH
    (SELECT maxIf(bet_date, product = 'Live')  FROM bi_sandbox.bi_total_eg_hourly) AS hist_max_live,
    (SELECT maxIf(bet_date, product = 'Slots') FROM bi_sandbox.bi_total_eg_hourly) AS hist_max_slots
SELECT
{ALIASES}
FROM
(
    SELECT * FROM bi_sandbox.bi_total_eg_hourly
    UNION ALL
    SELECT * FROM bi_sandbox.bi_total_eg_hourly_recent
    WHERE bet_date > if(product = 'Live', hist_max_live, hist_max_slots)
);
"""
open(f"{out}/03_history_mvs_and_view.sql", "w").write(q03)
print("ok")

# ---------------- deploy_all.sql = 00 + 02 + 03 without comment lines ----------------
import re
parts_ = ["-- Total EG: full deployment = 00_cleanup + 02 + 03 without comments (generated by gen/gen.py).",
          "-- Run in the ProdCH SQL console as an admin, top to bottom. Replace <RANDOM_PASSWORD> first.",
          "-- Then: SELECT view, status, exception FROM system.view_refreshes WHERE database = 'bi_sandbox' AND view LIKE 'bi_total_eg%';", ""]
for f in ["00_cleanup.sql", "02_history_tables.sql", "03_history_mvs_and_view.sql"]:
    lines = [l for l in open(f"{out}/{f}").read().splitlines() if not l.lstrip().startswith("--")]
    body = re.sub(r"\n\s*\n+", "\n\n", "\n".join(lines)).strip()
    parts_.append(f"-- ===== {f} =====\n{body}\n")
open(f"{out}/deploy_all.sql", "w").write("\n".join(parts_))
